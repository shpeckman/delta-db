# src/delta_db/storage.cr
require "sqlite3"

module DeltaDB
  class Storage
    OVERFLOW_THRESHOLD = 16
    DEFAULT_MMAP_SIZE  = 256_i64 << 20

    getter db : DB::Database

    def initialize(@db : DB::Database)
      migrate
    end

    def self.open(path : String, mmap_size : Int64 = DEFAULT_MMAP_SIZE) : Storage
      raise ArgumentError.new("mmap_size must be non-negative: #{mmap_size}") if mmap_size.negative?
      db = DB.open("sqlite3://#{path}")
      db.setup_connection { |conn| conn.exec("PRAGMA mmap_size = #{mmap_size}") }
      Storage.new(db)
    end

    def self.in_memory : Storage
      Storage.new(DB.open("sqlite3::memory:?max_pool_size=1&initial_pool_size=1"))
    end

    def close : Nil
      @db.close
    end

    def mmap_size : Int64
      @db.scalar("PRAGMA mmap_size").as(Int64)
    end

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
      migrate_history_dag
    end

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
      @db.transaction do |tx|
        conn = tx.connection
        key = history_conn(conn, history)
        actor_conn(conn, key, actor.value.to_s)
      end
    end

    private def actor_conn(conn : DB::Connection, key : Int64, actor : String) : Int64
      existing = conn.query_one?("SELECT actor_ordinal FROM history_actors WHERE history_key = ? AND actor = ?", key, actor) do |rs|
        rs.read(Int64)
      end
      existing || begin
        ordinal = conn.scalar("SELECT COALESCE(MAX(actor_ordinal) + 1, 0) FROM history_actors WHERE history_key = ?", key).as(Int64)
        conn.exec("INSERT INTO history_actors (history_key, actor_ordinal, actor) VALUES (?, ?, ?)", key, ordinal, actor)
        ordinal
      end
    end

    def insert_delta(delta : Delta) : Nil
      @db.transaction do |tx|
        conn = tx.connection
        key = history_conn(conn, delta.history)
        actor_conn(conn, key, delta.actor.value.to_s)
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
          "INSERT INTO history_delta_values (history_key, actor, timestamp, value, chunk_count, schema_version, value_len) VALUES (?, ?, ?, ?, ?, ?, ?)",
          key, actor, timestamp, inline, 1 + (value.size - OVERFLOW_THRESHOLD - 1) / OVERFLOW_THRESHOLD + 1, 0, value.size,
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
        inline = value.empty? ? Bytes[0u8] : value
        conn.exec(
          "INSERT INTO history_delta_values (history_key, actor, timestamp, value, chunk_count, schema_version, value_len) VALUES (?, ?, ?, ?, ?, ?, ?)",
          key, actor, timestamp, inline, 1, 0, value.size,
        )
      end
    end

    def delta_value(history : HistoryId, timestamp : Lamport) : Bytes?
      @db.using_connection { |conn| delta_value_conn(conn, history, timestamp) }
    end

    private def delta_value_conn(conn : DB::Connection, history : HistoryId, timestamp : Lamport) : Bytes?
      key = conn.query_one?("SELECT history_key FROM histories WHERE history_uuid = ?", history.value.bytes.to_slice) do |rs|
        rs.read(Int64)
      end
      return nil unless key

      actor = timestamp.replica_id.value.to_i64
      ts = timestamp.value.to_i64
      row = conn.query_one?(
        "SELECT value, pack_id, pack_offset, value_len FROM history_delta_values WHERE history_key = ? AND actor = ? AND timestamp = ?",
        key, actor, ts,
      ) do |rs|
        {rs.read(Bytes), rs.read(Int64?), rs.read(Int64?), rs.read(Int64?)}
      end
      return nil unless row

      inline, pack_id, pack_offset, value_len = row
      return read_pack_slice(conn, pack_id, (pack_offset || 0i64).to_i32, value_len.try(&.to_i32)) if pack_id
      return Bytes.empty if value_len == 0

      overflow = [] of Bytes
      conn.query(
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

    private def read_pack_slice(conn : DB::Connection, pack_id : Int64, offset : Int32, length : Int32?) : Bytes?
      handle = conn.as(SQLite3::Connection).to_unsafe
      return nil unless LibSQLite3Blob.open(handle, "main", "history_delta_value_packs", "data", pack_id, 0, out blob) == 0
      begin
        size = length || LibSQLite3Blob.bytes(blob) - offset
        bytes = Bytes.new(size)
        raise SQLite3::Exception.new(handle) unless LibSQLite3Blob.read(blob, bytes.to_unsafe, size, offset) == 0
        bytes
      ensure
        LibSQLite3Blob.close(blob)
      end
    end

    def append_delta(delta : Delta) : History::Version
      result : History::Version? = nil
      @db.transaction do |tx|
        conn = tx.connection
        key = history_conn(conn, delta.history)
        actor_conn(conn, key, delta.actor.value.to_s)
        timeline_actor = actor_conn(conn, key, delta.timeline.to_s)
        version_key = conn.scalar(
          "SELECT COALESCE(MAX(version_key) + 1, 0) FROM history_versions WHERE history_key = ?",
          key,
        ).as(Int64)
        batch_id = DeltaBatchId.new(delta.timeline.uuid, delta.timestamp.value.to_u64)
        version = History::Version.from_id(batch_id)
        version_text = version.encode_version_text({delta.timeline.uuid => timeline_actor})

        insert_delta(conn, key, delta)
        conn.exec(
          "INSERT INTO history_versions (history_key, version_key, version) VALUES (?, ?, ?)",
          key, version_key, version_text,
        )
        conn.exec(
          "INSERT INTO history_timelines (history_key, timeline_actor, timeline_timestamp, version, version_key) " \
          "VALUES (?, ?, ?, ?, ?) " \
          "ON CONFLICT(history_key, timeline_actor, timeline_timestamp) " \
          "DO UPDATE SET version = excluded.version, version_key = excluded.version_key",
          key, timeline_actor, delta.timeline.generation, version_text, version_key,
        )
        result = version
      end
      result.not_nil!
    end

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
