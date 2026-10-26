require "sqlite3"

module DeltaDB
  # A single delta: a header (id, parent, actor, timestamp) plus a byte payload.
  struct Delta
    getter id : DeltaId
    getter timeline_id : TimelineId
    getter parent_delta_id : DeltaId?
    getter actor : ActorUuid
    getter timestamp : Lamport
    getter value : Bytes

    def initialize(
      @id : DeltaId,
      @timeline_id : TimelineId,
      @parent_delta_id : DeltaId?,
      @actor : ActorUuid,
      @timestamp : Lamport,
      @value : Bytes,
    )
    end
  end

  # SQLite-backed storage for the delta/history engine.
  #
  # Clean-room schema (own design) capturing the semantics recovered from
  # `deltadb::storage`: deltas (header + value with overflow chunks), timelines,
  # actors, versions, and schema metadata.
  class Storage
    # Values larger than this many bytes spill into overflow chunks.
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
        "CREATE TABLE IF NOT EXISTS app_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)",
        "CREATE TABLE IF NOT EXISTS actors (actor_uuid TEXT PRIMARY KEY, last_seen_at INTEGER NOT NULL)",
        "CREATE TABLE IF NOT EXISTS timelines (timeline_id TEXT PRIMARY KEY, history_id TEXT NOT NULL, head_delta_id TEXT)",
        "CREATE TABLE IF NOT EXISTS deltas (" \
          "delta_id TEXT PRIMARY KEY, timeline_id TEXT NOT NULL, parent_delta_id TEXT, " \
          "actor_uuid TEXT NOT NULL, timestamp_value INTEGER NOT NULL, " \
          "timestamp_replica_id INTEGER NOT NULL, value BLOB NOT NULL)",
        "CREATE TABLE IF NOT EXISTS delta_value_overflow_chunks (" \
          "delta_id TEXT NOT NULL, chunk_index INTEGER NOT NULL, chunk BLOB NOT NULL, " \
          "PRIMARY KEY (delta_id, chunk_index))",
        "CREATE TABLE IF NOT EXISTS versions (" \
          "timeline_id TEXT NOT NULL, version INTEGER NOT NULL, delta_id TEXT NOT NULL, " \
          "PRIMARY KEY (timeline_id, version))",
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

    # -- actors / timelines -------------------------------------------------

    def record_actor(actor : ActorUuid, at : Int64) : Nil
      @db.exec("INSERT OR REPLACE INTO actors (actor_uuid, last_seen_at) VALUES (?, ?)", actor.value.to_s, at)
    end

    def ensure_timeline(timeline_id : TimelineId, history_id : HistoryId) : Nil
      @db.exec(
        "INSERT OR IGNORE INTO timelines (timeline_id, history_id) VALUES (?, ?)",
        timeline_id.value.to_s, history_id.value.to_s,
      )
    end

    # -- deltas -------------------------------------------------------------

    # Insert a delta (header + value). Large values spill into overflow chunks.
    def insert_delta(delta : Delta) : Nil
      @db.transaction do |tx|
        insert_delta(tx.connection, delta)
      end
    end

    private def insert_delta(conn : DB::Connection, delta : Delta) : Nil
      value = delta.value
      if value.size > OVERFLOW_THRESHOLD
        inline = value[0, OVERFLOW_THRESHOLD]
        conn.exec(
          "INSERT INTO deltas (delta_id, timeline_id, parent_delta_id, actor_uuid, timestamp_value, timestamp_replica_id, value) VALUES (?, ?, ?, ?, ?, ?, ?)",
          delta.id.value.to_s,
          delta.timeline_id.value.to_s,
          delta.parent_delta_id.try(&.value.to_s),
          delta.actor.value.to_s,
          delta.timestamp.value.to_i64,
          delta.timestamp.replica_id.value.to_i32,
          inline,
        )
        chunk_index = 0
        offset = OVERFLOW_THRESHOLD
        while offset < value.size
          chunk = value[offset, Math.min(OVERFLOW_THRESHOLD, value.size - offset)]
          conn.exec(
            "INSERT INTO delta_value_overflow_chunks (delta_id, chunk_index, chunk) VALUES (?, ?, ?)",
            delta.id.value.to_s, chunk_index, chunk,
          )
          chunk_index += 1
          offset += OVERFLOW_THRESHOLD
        end
      else
        conn.exec(
          "INSERT INTO deltas (delta_id, timeline_id, parent_delta_id, actor_uuid, timestamp_value, timestamp_replica_id, value) VALUES (?, ?, ?, ?, ?, ?, ?)",
          delta.id.value.to_s,
          delta.timeline_id.value.to_s,
          delta.parent_delta_id.try(&.value.to_s),
          delta.actor.value.to_s,
          delta.timestamp.value.to_i64,
          delta.timestamp.replica_id.value.to_i32,
          value,
        )
      end
    end

    # Read and reassemble a delta's full value (inline + overflow chunks).
    def delta_value(delta_id : DeltaId) : Bytes?
      inline = @db.query_one?("SELECT value FROM deltas WHERE delta_id = ?", delta_id.value.to_s) do |rs|
        rs.read(Bytes)
      end
      return nil unless inline

      overflow = [] of Bytes
      @db.query(
        "SELECT chunk FROM delta_value_overflow_chunks WHERE delta_id = ? ORDER BY chunk_index",
        delta_id.value.to_s,
      ) do |rs|
        rs.each do
          overflow << rs.read(Bytes)
        end
      end

      return inline if overflow.empty?

      io = IO::Memory.new
      io.write(inline)
      overflow.each { |chunk| io.write(chunk) }
      io.to_slice
    end

    def delta_header(delta_id : DeltaId) : Delta?
      header = @db.query_one?(
        "SELECT delta_id, timeline_id, parent_delta_id, actor_uuid, timestamp_value, timestamp_replica_id FROM deltas WHERE delta_id = ?",
        delta_id.value.to_s,
      ) do |rs|
        {
          DeltaId.new(UUID.new(rs.read(String))),
          TimelineId.new(UUID.new(rs.read(String))),
          rs.read(String?).try { |s| DeltaId.new(UUID.new(s)) },
          ActorUuid.new(UUID.new(rs.read(String))),
          rs.read(Int64).to_u32,
          rs.read(Int64).to_u16,
        }
      end
      return nil unless header

      id, timeline, parent, actor, ts_value, ts_replica = header
      value = delta_value(id) || Bytes.empty
      Delta.new(id, timeline, parent, actor, Lamport.new(ReplicaId.new(ts_replica), ts_value), value)
    end

    # -- timeline append / versions ----------------------------------------

    # Append a delta to its timeline, assigning the next monotonic version and
    # advancing the timeline head. Returns the assigned version.
    def append_delta(delta : Delta) : HistoryVersion
      result : HistoryVersion? = nil
      @db.transaction do |tx|
        conn = tx.connection
        version = conn.scalar(
          "SELECT COALESCE(MAX(version) + 1, 0) FROM versions WHERE timeline_id = ?",
          delta.timeline_id.value.to_s,
        ).as(Int64)

        insert_delta(conn, delta)
        conn.exec(
          "INSERT INTO versions (timeline_id, version, delta_id) VALUES (?, ?, ?)",
          delta.timeline_id.value.to_s, version, delta.id.value.to_s,
        )
        conn.exec(
          "UPDATE timelines SET head_delta_id = ? WHERE timeline_id = ?",
          delta.id.value.to_s, delta.timeline_id.value.to_s,
        )
        result = HistoryVersion.new(version.to_u64)
      end
      result.not_nil!
    end

    def timeline_head(timeline_id : TimelineId) : DeltaId?
      @db.query_one?(
        "SELECT head_delta_id FROM timelines WHERE timeline_id = ?",
        timeline_id.value.to_s,
      ) do |rs|
        rs.read(String?).try { |s| DeltaId.new(UUID.new(s)) }
      end
    end

    def delta_at_version(timeline_id : TimelineId, version : HistoryVersion) : DeltaId?
      @db.query_one?(
        "SELECT delta_id FROM versions WHERE timeline_id = ? AND version = ?",
        timeline_id.value.to_s, version.value.to_i64,
      ) do |rs|
        DeltaId.new(UUID.new(rs.read(String)))
      end
    end
  end
end
