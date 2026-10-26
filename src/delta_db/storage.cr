require "sqlite3"

module DeltaDB
  # A single delta: its storage identity is `(history, actor, timestamp)` plus a
  # byte payload.
  struct Delta
    getter history : HistoryId
    getter timeline : TimelineId
    getter actor : ActorUuid
    getter timestamp : Lamport
    getter value : Bytes

    def initialize(
      @history : HistoryId,
      @timeline : TimelineId,
      @actor : ActorUuid,
      @timestamp : Lamport,
      @value : Bytes,
    )
    end
  end

  # SQLite-backed storage for the delta/history engine.
  #
  # The schema now matches the real Delta `data.sqlite` (recovered + validated):
  # `histories` (integer `history_key` + `history_uuid` blob), `history_delta_values`
  # keyed by `(history_key, actor, timestamp)`, `history_versions` with a
  # `version TEXT` (encoded `DeltaBatchId`) + integer `version_key`, `history_actors`,
  # plus `app_meta`/`metadata` key-value tables. `WITHOUT ROWID` where the real
  # tables use it.
  class Storage
    OVERFLOW_THRESHOLD = 16

    getter db : DB::Database

    def initialize(@db : DB::Database)
      migrate
    end

    def self.open(path : String) : Storage
      Storage.new(DB.open("sqlite3://#{path}"))
    end

    def self.in_memory : Storage
      Storage.new(DB.open("sqlite3::memory:?max_pool_size=1&initial_pool_size=1"))
    end

    def close : Nil
      @db.close
    end

    # -- schema ------------------------------------------------------------

    private def migrate : Nil
      [
        "CREATE TABLE IF NOT EXISTS histories (" \
        "history_key INTEGER PRIMARY KEY, history_uuid BLOB NOT NULL UNIQUE, " \
        "max_timestamp INTEGER NOT NULL DEFAULT 0, epoch_count INTEGER NOT NULL DEFAULT 0, " \
        "run_format INTEGER NOT NULL DEFAULT 0)",
        "CREATE TABLE IF NOT EXISTS history_delta_values (" \
        "history_key INTEGER NOT NULL, actor INTEGER NOT NULL, timestamp INTEGER NOT NULL, " \
        "value BLOB NOT NULL, chunk_count INTEGER NOT NULL DEFAULT 1, " \
        "schema_version INTEGER NOT NULL, pack_id INTEGER, pack_offset INTEGER, value_len INTEGER, " \
        "PRIMARY KEY (history_key, actor, timestamp)) WITHOUT ROWID",
        "CREATE TABLE IF NOT EXISTS history_delta_value_overflow_chunks (" \
        "history_key INTEGER NOT NULL, actor INTEGER NOT NULL, timestamp INTEGER NOT NULL, " \
        "chunk_index INTEGER NOT NULL, data BLOB NOT NULL, " \
        "PRIMARY KEY (history_key, actor, timestamp, chunk_index)) WITHOUT ROWID",
        "CREATE TABLE IF NOT EXISTS history_versions (" \
        "history_key INTEGER NOT NULL, version_key INTEGER NOT NULL, version TEXT NOT NULL, " \
        "PRIMARY KEY (history_key, version_key), UNIQUE (history_key, version)) WITHOUT ROWID",
        "CREATE TABLE IF NOT EXISTS history_actors (" \
        "history_key INTEGER NOT NULL, actor_ordinal INTEGER NOT NULL, actor TEXT NOT NULL, " \
        "PRIMARY KEY (history_key, actor_ordinal), UNIQUE (history_key, actor)) WITHOUT ROWID",
        "CREATE TABLE IF NOT EXISTS history_timelines (" \
        "history_key INTEGER NOT NULL, timeline_actor INTEGER NOT NULL, " \
        "timeline_timestamp INTEGER NOT NULL, version TEXT, version_key INTEGER, " \
        "PRIMARY KEY (history_key, timeline_actor, timeline_timestamp)) WITHOUT ROWID",
        "CREATE TABLE IF NOT EXISTS app_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)",
        "CREATE TABLE IF NOT EXISTS metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)",
      ].each do |sql|
        @db.exec(sql)
      end
    end

    # -- app_meta ----------------------------------------------------------

    def meta_get(key : String) : String?
      @db.query_one?("SELECT value FROM app_meta WHERE key = ?", key) do |rs|
        rs.read(String)
      end
    end

    def meta_set(key : String, value : String) : Nil
      @db.exec("INSERT OR REPLACE INTO app_meta (key, value) VALUES (?, ?)", key, value)
    end

    def schema_version : Int32
      meta_get("schema_version").try(&.to_i) || 0
    end

    def schema_version=(version : Int32) : Nil
      meta_set("schema_version", version.to_s)
    end

    # -- histories ---------------------------------------------------------

    # Resolve (or create) the integer `history_key` for a `HistoryId`.
    def history_key_for(history : HistoryId) : Int64
      uuid = history.value.bytes.to_slice
      key = @db.query_one?("SELECT history_key FROM histories WHERE history_uuid = ?", uuid) do |rs|
        rs.read(Int64)
      end
      key || begin
        @db.exec("INSERT INTO histories (history_uuid) VALUES (?)", uuid)
        @db.scalar("SELECT last_insert_rowid()").as(Int64)
      end
    end

    def record_actor(history : HistoryId, actor : ActorUuid) : Nil
      key = history_key_for(history)
      ordinal = @db.scalar("SELECT COALESCE(MAX(actor_ordinal) + 1, 0) FROM history_actors WHERE history_key = ?", key).as(Int64)
      @db.exec("INSERT OR IGNORE INTO history_actors (history_key, actor_ordinal, actor) VALUES (?, ?, ?)", key, ordinal, actor.value.to_s)
    end

    # -- deltas -------------------------------------------------------------

    # Insert a delta (header + value). Large values spill into overflow chunks.
    def insert_delta(delta : Delta) : Nil
      @db.transaction do |tx|
        conn = tx.connection
        key = history_conn(conn, delta.history)
        insert_delta(conn, key, delta)
      end
    end

    private def insert_delta(conn : DB::Connection, key : Int64, delta : Delta) : Nil
      actor = delta.timestamp.replica_id.value.to_i64
      timestamp = delta.timestamp.value.to_i64
      value = delta.value
      if value.size > OVERFLOW_THRESHOLD
        inline = value[0, OVERFLOW_THRESHOLD]
        conn.exec(
          "INSERT INTO history_delta_values (history_key, actor, timestamp, value, chunk_count, schema_version) VALUES (?, ?, ?, ?, ?, ?)",
          key, actor, timestamp, inline, 1 + (value.size - OVERFLOW_THRESHOLD - 1) / OVERFLOW_THRESHOLD + 1, 0,
        )
        chunk_index = 0
        offset = OVERFLOW_THRESHOLD
        while offset < value.size
          chunk = value[offset, Math.min(OVERFLOW_THRESHOLD, value.size - offset)]
          conn.exec(
            "INSERT INTO history_delta_value_overflow_chunks (history_key, actor, timestamp, chunk_index, data) VALUES (?, ?, ?, ?, ?)",
            key, actor, timestamp, chunk_index, chunk,
          )
          chunk_index += 1
          offset += OVERFLOW_THRESHOLD
        end
      else
        conn.exec(
          "INSERT INTO history_delta_values (history_key, actor, timestamp, value, chunk_count, schema_version) VALUES (?, ?, ?, ?, ?, ?)",
          key, actor, timestamp, value, 1, 0,
        )
      end
    end

    # Read and reassemble a delta's full value (inline + overflow chunks).
    def delta_value(history : HistoryId, timestamp : Lamport) : Bytes?
      key = @db.query_one?("SELECT history_key FROM histories WHERE history_uuid = ?", history.value.bytes.to_slice) do |rs|
        rs.read(Int64)
      end
      return nil unless key

      actor = timestamp.replica_id.value.to_i64
      ts = timestamp.value.to_i64
      inline = @db.query_one?(
        "SELECT value FROM history_delta_values WHERE history_key = ? AND actor = ? AND timestamp = ?",
        key, actor, ts,
      ) do |rs|
        rs.read(Bytes)
      end
      return nil unless inline

      overflow = [] of Bytes
      @db.query(
        "SELECT data FROM history_delta_value_overflow_chunks WHERE history_key = ? AND actor = ? AND timestamp = ? ORDER BY chunk_index",
        key, actor, ts,
      ) do |rs|
        rs.each { overflow << rs.read(Bytes) }
      end

      return inline if overflow.empty?

      io = IO::Memory.new
      io.write(inline)
      overflow.each { |chunk| io.write(chunk) }
      io.to_slice
    end

    # -- timeline append / versions ----------------------------------------

    # Append a delta, assigning the next version and advancing the timeline head.
    def append_delta(delta : Delta) : HistoryVersion
      result : HistoryVersion? = nil
      @db.transaction do |tx|
        conn = tx.connection
        key = history_conn(conn, delta.history)
        version_key = conn.scalar(
          "SELECT COALESCE(MAX(version_key) + 1, 0) FROM history_versions WHERE history_key = ?",
          key,
        ).as(Int64)
        batch_id = DeltaBatchId.new(delta.timeline.uuid, version_key.to_u64)
        version = batch_id.to_s

        insert_delta(conn, key, delta)
        conn.exec(
          "INSERT INTO history_versions (history_key, version_key, version) VALUES (?, ?, ?)",
          key, version_key, version,
        )
        conn.exec(
          "UPDATE history_timelines SET version = ?, version_key = ? WHERE history_key = ?",
          version, version_key, key,
        )
        result = HistoryVersion.new(batch_id)
      end
      result.not_nil!
    end

    # Resolve the history_key without using the pooled connection (for tx use).
    private def history_conn(conn : DB::Connection, history : HistoryId) : Int64
      uuid = history.value.bytes.to_slice
      conn.query_one?("SELECT history_key FROM histories WHERE history_uuid = ?", uuid) do |rs|
        rs.read(Int64)
      end || begin
        conn.exec("INSERT INTO histories (history_uuid) VALUES (?)", uuid)
        conn.scalar("SELECT last_insert_rowid()").as(Int64)
      end
    end
  end
end
