# src/delta_db/storage_history.cr
module DeltaDB
  class Storage
    CURRENT_SCHEMA_VERSION = 2

    private def migrate_history_dag : Nil
      current = schema_version
      if current > CURRENT_SCHEMA_VERSION
        raise ArgumentError.new("database schema #{current} is newer than supported schema #{CURRENT_SCHEMA_VERSION}")
      end

      [
        "CREATE TABLE IF NOT EXISTS history_delta_value_packs (" \
        "pack_id INTEGER PRIMARY KEY AUTOINCREMENT, history_key INTEGER NOT NULL, " \
        "schema_version INTEGER NOT NULL, data BLOB NOT NULL)",
        "CREATE TABLE IF NOT EXISTS history_delta_batches (" \
        "history_key INTEGER NOT NULL, actor INTEGER NOT NULL, timestamp INTEGER NOT NULL, " \
        "timeline_actor INTEGER NOT NULL, timeline_timestamp INTEGER NOT NULL, " \
        "delta_actor TEXT NOT NULL, epoch INTEGER NOT NULL, parents TEXT NOT NULL, " \
        "PRIMARY KEY (history_key, actor, timestamp)) WITHOUT ROWID",
        "CREATE TABLE IF NOT EXISTS history_delta_batch_parents (" \
        "history_key INTEGER NOT NULL, actor INTEGER NOT NULL, timestamp INTEGER NOT NULL, " \
        "parent_actor INTEGER NOT NULL, parent_timestamp INTEGER NOT NULL, " \
        "PRIMARY KEY (history_key, actor, timestamp, parent_actor, parent_timestamp)) WITHOUT ROWID",
        "CREATE TABLE IF NOT EXISTS history_timeline_metadata (" \
        "history_key INTEGER NOT NULL, timeline_actor INTEGER NOT NULL, timeline_timestamp INTEGER NOT NULL, " \
        "parent_actor INTEGER, parent_timestamp INTEGER, reset_generation INTEGER NOT NULL, origin TEXT NOT NULL, " \
        "PRIMARY KEY (history_key, timeline_actor, timeline_timestamp)) WITHOUT ROWID",
        "CREATE TABLE IF NOT EXISTS history_epochs (" \
        "history_key INTEGER NOT NULL, epoch INTEGER NOT NULL, start_version TEXT NOT NULL, " \
        "PRIMARY KEY (history_key, epoch)) WITHOUT ROWID",
        "CREATE TABLE IF NOT EXISTS history_run_headers (" \
        "history_key INTEGER NOT NULL, run_actor INTEGER NOT NULL, run_timestamp INTEGER NOT NULL, " \
        "delta_count INTEGER NOT NULL, PRIMARY KEY (history_key, run_actor, run_timestamp)) WITHOUT ROWID",
        "CREATE TABLE IF NOT EXISTS history_run_segments (" \
        "history_key INTEGER NOT NULL, run_actor INTEGER NOT NULL, run_timestamp INTEGER NOT NULL, " \
        "segment_index INTEGER NOT NULL, delta_id TEXT NOT NULL, " \
        "PRIMARY KEY (history_key, run_actor, run_timestamp, segment_index)) WITHOUT ROWID",
        "CREATE TABLE IF NOT EXISTS history_checkpoint_dag_state (" \
        "history_key INTEGER PRIMARY KEY, version TEXT NOT NULL, " \
        "max_timestamp INTEGER NOT NULL, epoch_count INTEGER NOT NULL)",
      ].each do |sql|
        @db.exec(sql)
      end
      self.schema_version = CURRENT_SCHEMA_VERSION if current < CURRENT_SCHEMA_VERSION
    end

    def save_batch(history : HistoryId, batch : HistoryDeltaBatch) : Nil
      @db.transaction do |tx|
        conn = tx.connection
        key = history_conn(conn, history)
        insert_batch_conn(conn, key, batch)
        timeline = dag_timeline_for_batch(batch)
        save_timeline_conn(conn, key, timeline)
      end
    end

    def save_dag(dag : HistoryDag) : Nil
      @db.transaction do |tx|
        conn = tx.connection
        key = history_conn(conn, dag.history_id)
        save_dag_conn(conn, key, dag)
      end
    end

    def load_dag(history : HistoryId) : HistoryDag
      key = @db.query_one?("SELECT history_key FROM histories WHERE history_uuid = ?", history.value.bytes.to_slice) do |rs|
        rs.read(Int64)
      end
      return HistoryDag.new(history) unless key

      snapshot = HistoryDagSnapshot.new(history)
      timelines = [] of HistoryTimeline
      @db.query("SELECT timeline_actor, timeline_timestamp, version FROM history_timelines WHERE history_key = ?", key) do |rs|
        rs.each do
          timeline_actor = rs.read(Int64)
          rs.read(Int64)
          version = rs.read(String?)
          id = timeline_actor_conn(@db, key, timeline_actor)
          head = version ? decode_version_conn(@db, key, version) : HistoryVersion.new
          origin = head
          parent : TimelineId? = nil
          reset_generation = id.generation
          @db.query_one?("SELECT parent_actor, parent_timestamp, reset_generation, origin FROM history_timeline_metadata WHERE history_key = ? AND timeline_actor = ? AND timeline_timestamp = ?", key, timeline_actor, id.generation) do |metadata|
            parent_actor = metadata.read(Int64?)
            metadata.read(Int64?)
            reset_generation = metadata.read(Int64).to_u32
            origin_text = metadata.read(String)
            origin = decode_version_conn(@db, key, origin_text)
            parent = timeline_actor_conn(@db, key, parent_actor) if parent_actor
          end
          timelines << HistoryTimeline.new(id, head, origin, parent, reset_generation)
        end
      end

      epochs = [] of HistoryEpoch
      @db.query("SELECT epoch, start_version FROM history_epochs WHERE history_key = ? ORDER BY epoch", key) do |rs|
        rs.each { epochs << HistoryEpoch.new(rs.read(Int64).to_u64, decode_version_conn(@db, key, rs.read(String))) }
      end

      batches = [] of HistoryDeltaBatch
      @db.query("SELECT actor, timestamp, timeline_actor, timeline_timestamp, delta_actor, epoch, parents FROM history_delta_batches WHERE history_key = ? ORDER BY actor, timestamp", key) do |rs|
        rs.each do
          actor = rs.read(Int64)
          timestamp = rs.read(Int64).to_u64
          timeline_actor = rs.read(Int64)
          rs.read(Int64)
          delta_actor = rs.read(String)
          epoch = rs.read(Int64).to_u64
          parents = decode_version_conn(@db, key, rs.read(String))
          timeline = timeline_actor_conn(@db, key, timeline_actor)
          batches << HistoryDeltaBatch.new(
            DeltaBatchId.new(timeline.uuid, timestamp),
            timeline,
            ActorUuid.new(UUID.new(delta_actor)),
            parents,
            [] of Delta,
            epoch,
          )
        end
      end

      max_timestamp, epoch_count = @db.query_one("SELECT max_timestamp, epoch_count FROM histories WHERE history_key = ?", key) do |rs|
        {rs.read(Int64).to_u64, rs.read(Int64).to_u64}
      end
      HistoryDag.from_snapshot(HistoryDagSnapshot.new(history, batches, timelines, epochs, max_timestamp, epoch_count))
    end

    def checkpoint(history : HistoryId) : HistoryDagSnapshot
      load_dag(history).checkpoint
    end

    def install_checkpoint(snapshot : HistoryDagSnapshot) : Nil
      dag = HistoryDag.from_snapshot(snapshot)
      @db.transaction do |tx|
        conn = tx.connection
        key = history_conn(conn, snapshot.history_id)
        conn.exec("DELETE FROM history_delta_batch_parents WHERE history_key = ?", key)
        conn.exec("DELETE FROM history_delta_batches WHERE history_key = ?", key)
        conn.exec("DELETE FROM history_timeline_metadata WHERE history_key = ?", key)
        conn.exec("DELETE FROM history_timelines WHERE history_key = ?", key)
        conn.exec("DELETE FROM history_epochs WHERE history_key = ?", key)
        conn.exec("DELETE FROM history_checkpoint_dag_state WHERE history_key = ?", key)
        save_dag_conn(conn, key, dag)
      end
    end

    def record_checkpoint(history : HistoryId, version : HistoryVersion) : Nil
      @db.transaction do |tx|
        conn = tx.connection
        key = history_conn(conn, history)
        text = encode_version_conn(conn, key, version)
        max_timestamp = version.ids.max_of?(&.ordinal) || 0u64
        conn.exec(
          "INSERT OR REPLACE INTO history_checkpoint_dag_state (history_key, version, max_timestamp, epoch_count) VALUES (?, ?, ?, ?)",
          key, text, max_timestamp.to_i64, 0,
        )
      end
    end

    def checkpoint_version(history : HistoryId) : HistoryVersion?
      key = @db.query_one?("SELECT history_key FROM histories WHERE history_uuid = ?", history.value.bytes.to_slice) do |rs|
        rs.read(Int64)
      end
      return nil unless key
      text = @db.query_one?("SELECT version FROM history_checkpoint_dag_state WHERE history_key = ?", key) do |rs|
        rs.read(String)
      end
      text ? decode_version_conn(@db, key, text) : nil
    end

    def pack_deltas(history : HistoryId, deltas : Array(Delta)) : Int64
      result = 0i64
      @db.transaction do |tx|
        conn = tx.connection
        key = history_conn(conn, history)
        payload = IO::Memory.new
        offsets = deltas.map do |delta|
          offset = payload.pos
          payload.write(delta.value)
          {offset, delta.value.size}
        end
        conn.exec("INSERT INTO history_delta_value_packs (history_key, schema_version, data) VALUES (?, ?, ?)", key, 0, payload.to_slice)
        pack_id = conn.scalar("SELECT last_insert_rowid()").as(Int64)
        deltas.each_with_index do |delta, index|
          actor_conn(conn, key, delta.actor.value.to_s)
          offset, length = offsets[index]
          conn.exec(
            "INSERT OR REPLACE INTO history_delta_values (history_key, actor, timestamp, value, chunk_count, schema_version, pack_id, pack_offset, value_len) " \
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            key, delta.timestamp.replica_id.value.to_i64, delta.timestamp.value.to_i64,
            Bytes[0u8], 1, 0, pack_id, offset, length,
          )
        end
        result = pack_id
      end
      result
    end

    def append_run(history : HistoryId, run : DeltaRun) : Nil
      @db.transaction do |tx|
        conn = tx.connection
        key = history_conn(conn, history)
        actor = run.actor.value.to_i64
        timestamp = run.timestamp.value.to_i64
        conn.exec(
          "INSERT OR REPLACE INTO history_run_headers (history_key, run_actor, run_timestamp, delta_count) VALUES (?, ?, ?, ?)",
          key, actor, timestamp, run.delta_ids.size,
        )
        conn.exec("DELETE FROM history_run_segments WHERE history_key = ? AND run_actor = ? AND run_timestamp = ?", key, actor, timestamp)
        run.delta_ids.each_with_index do |delta_id, index|
          conn.exec(
            "INSERT INTO history_run_segments (history_key, run_actor, run_timestamp, segment_index, delta_id) VALUES (?, ?, ?, ?, ?)",
            key, actor, timestamp, index, delta_id.to_s,
          )
        end
      end
    end

    def load_runs(history : HistoryId) : Array(DeltaRun)
      runs = [] of DeltaRun
      @db.query("SELECT run_actor, run_timestamp FROM history_run_headers WHERE history_key = ? ORDER BY run_actor, run_timestamp", history_key_for(history)) do |rs|
        rs.each do
          actor = rs.read(Int64).to_u16
          timestamp = rs.read(Int64).to_u32
          replica = ReplicaId.new(actor)
          ids = [] of DeltaId
          @db.query("SELECT delta_id FROM history_run_segments WHERE history_key = ? AND run_actor = ? AND run_timestamp = ? ORDER BY segment_index", history_key_for(history), actor, timestamp) do |segments|
            segments.each { ids << DeltaId.new(UUID.new(segments.read(String))) }
          end
          runs << DeltaRun.new(replica, Lamport.new(replica, timestamp), ids)
        end
      end
      runs
    end

    private def save_dag_conn(conn : DB::Connection, key : Int64, dag : HistoryDag) : Nil
      dag.timelines.each_value { |timeline| save_timeline_conn(conn, key, timeline) }
      dag.epochs.each do |epoch|
        start_version, _ = version_row_conn(conn, key, epoch.start_version)
        conn.exec(
          "INSERT OR REPLACE INTO history_epochs (history_key, epoch, start_version) VALUES (?, ?, ?)",
          key, epoch.epoch.to_i64, start_version,
        )
      end
      dag.batches.each_value { |batch| insert_batch_conn(conn, key, batch) }
      conn.exec(
        "UPDATE histories SET max_timestamp = ?, epoch_count = ? WHERE history_key = ?",
        dag.max_timestamp.to_i64, dag.epoch_count.to_i64, key,
      )
      checkpoint_text = encode_version_conn(conn, key, dag.timeline_version)
      conn.exec(
        "INSERT OR REPLACE INTO history_checkpoint_dag_state (history_key, version, max_timestamp, epoch_count) VALUES (?, ?, ?, ?)",
        key, checkpoint_text, dag.max_timestamp.to_i64, dag.epoch_count.to_i64,
      )
    end

    private def insert_batch_conn(conn : DB::Connection, key : Int64, batch : HistoryDeltaBatch) : Nil
      timeline_actor = actor_conn(conn, key, batch.timeline.to_s)
      actor_conn(conn, key, batch.actor.value.to_s)
      parents = encode_version_conn(conn, key, batch.parents)
      actor = timeline_actor
      conn.exec(
        "INSERT OR REPLACE INTO history_delta_batches (history_key, actor, timestamp, timeline_actor, timeline_timestamp, delta_actor, epoch, parents) " \
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        key, actor, batch.id.ordinal.to_i64, timeline_actor, batch.timeline.generation.to_i64,
        batch.actor.value.to_s, batch.epoch.to_i64, parents,
      )
      conn.exec("DELETE FROM history_delta_batch_parents WHERE history_key = ? AND actor = ? AND timestamp = ?", key, actor, batch.id.ordinal.to_i64)
      batch.parents.ids.each do |parent|
        parent_actor = actor_conn(conn, key, parent.uuid.to_s)
        conn.exec(
          "INSERT INTO history_delta_batch_parents (history_key, actor, timestamp, parent_actor, parent_timestamp) VALUES (?, ?, ?, ?, ?)",
          key, actor, batch.id.ordinal.to_i64, parent_actor, parent.ordinal.to_i64,
        )
      end
      batch.deltas.each { |delta| insert_delta(conn, key, delta) }
    end

    private def save_timeline_conn(conn : DB::Connection, key : Int64, timeline : HistoryTimeline) : Nil
      timeline_actor = actor_conn(conn, key, timeline.id.to_s)
      version_text, version_key = version_row_conn(conn, key, timeline.head)
      conn.exec(
        "INSERT INTO history_timelines (history_key, timeline_actor, timeline_timestamp, version, version_key) " \
        "VALUES (?, ?, ?, ?, ?) ON CONFLICT(history_key, timeline_actor, timeline_timestamp) " \
        "DO UPDATE SET version = excluded.version, version_key = excluded.version_key",
        key, timeline_actor, timeline.id.generation.to_i64, version_text, version_key,
      )
      parent_actor = timeline.parent.try { |parent| actor_conn(conn, key, parent.to_s) }
      origin_text, _ = version_row_conn(conn, key, timeline.origin)
      conn.exec(
        "INSERT OR REPLACE INTO history_timeline_metadata (history_key, timeline_actor, timeline_timestamp, parent_actor, parent_timestamp, reset_generation, origin) " \
        "VALUES (?, ?, ?, ?, ?, ?, ?)",
        key, timeline_actor, timeline.id.generation.to_i64, parent_actor, timeline.parent.try { |parent| parent.generation.to_i64 }, timeline.reset_generation.to_i64, origin_text,
      )
    end

    private def dag_timeline_for_batch(batch : HistoryDeltaBatch) : HistoryTimeline
      HistoryTimeline.new(batch.timeline, HistoryVersion.from_id(batch.id), batch.parents)
    end

    private def version_row_conn(conn : DB::Connection, key : Int64, version : HistoryVersion) : {String, Int64}
      text = encode_version_conn(conn, key, version)
      existing = conn.query_one?("SELECT version_key FROM history_versions WHERE history_key = ? AND version = ?", key, text) do |rs|
        rs.read(Int64)
      end
      return {text, existing} if existing

      version_key = conn.scalar("SELECT COALESCE(MAX(version_key) + 1, 0) FROM history_versions WHERE history_key = ?", key).as(Int64)
      conn.exec("INSERT INTO history_versions (history_key, version_key, version) VALUES (?, ?, ?)", key, version_key, text)
      {text, version_key}
    end

    private def encode_version_conn(conn : DB::Connection, key : Int64, version : HistoryVersion) : String
      actors = Hash(UUID, Int64).new
      version.ids.each { |id| actors[id.uuid] = actor_conn(conn, key, id.uuid.to_s) }
      version.encode_version_text(actors)
    end

    private def decode_version_conn(conn : DB::Connection | DB::Database, key : Int64, text : String) : HistoryVersion
      actors = Hash(Int64, TimelineId).new
      conn.query("SELECT actor_ordinal, actor FROM history_actors WHERE history_key = ?", key) do |rs|
        rs.each { actors[rs.read(Int64)] = TimelineId.parse(rs.read(String)) }
      end
      HistoryVersion.decode_version_text(text, actors)
    end

    private def timeline_actor_conn(conn : DB::Connection | DB::Database, key : Int64, ordinal : Int64) : TimelineId
      actor = conn.query_one("SELECT actor FROM history_actors WHERE history_key = ? AND actor_ordinal = ?", key, ordinal) do |rs|
        rs.read(String)
      end
      TimelineId.parse(actor)
    end
  end
end
