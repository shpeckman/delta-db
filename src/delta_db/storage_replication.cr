# src/delta_db/storage_replication.cr
module DeltaDB
  class Storage
    private def migrate_replication : Nil
      [
        "CREATE TABLE IF NOT EXISTS history_checkpoint_publications (" \
        "id TEXT PRIMARY KEY, history_key INTEGER NOT NULL, version TEXT NOT NULL, " \
        "phase TEXT NOT NULL, encoded TEXT NOT NULL, last_error TEXT)",
        "CREATE TABLE IF NOT EXISTS history_replication_outbox (" \
        "id TEXT PRIMARY KEY, history_key INTEGER NOT NULL, pack TEXT NOT NULL, " \
        "state TEXT NOT NULL, last_error TEXT)",
        "CREATE TABLE IF NOT EXISTS history_connection_states (" \
        "history_key INTEGER PRIMARY KEY, local_version TEXT NOT NULL, remote_version TEXT NOT NULL, " \
        "reset_generation INTEGER NOT NULL, status TEXT NOT NULL, last_error TEXT)",
      ].each do |sql|
        @db.exec(sql)
      end
    end

    def insert_checkpoint_publication(publication : CheckpointPublication) : Nil
      @db.transaction do |tx|
        conn = tx.connection
        key = history_conn(conn, publication.history_id)
        version, _ = version_row_conn(conn, key, publication.version)
        conn.exec(
          "INSERT OR REPLACE INTO history_checkpoint_publications (id, history_key, version, phase, encoded, last_error) VALUES (?, ?, ?, ?, ?, ?)",
          publication.id, key, version, publication.phase.to_s, publication.encoded, publication.last_error,
        )
      end
    end

    def transition_checkpoint_publication_phase(id : String, phase : CheckpointPublicationPhase, error : String? = nil) : Nil
      @db.exec("UPDATE history_checkpoint_publications SET phase = ?, last_error = ? WHERE id = ?", phase.to_s, error, id)
    end

    def checkpoint_publication(id : String) : CheckpointPublication?
      row = @db.query_one?("SELECT history_key, version, phase, encoded, last_error FROM history_checkpoint_publications WHERE id = ?", id) do |rs|
        {rs.read(Int64), rs.read(String), rs.read(String), rs.read(String), rs.read(String?)}
      end
      return nil unless row
      key, version, phase, encoded, error = row
      CheckpointPublication.new(id, history_for_key(key), decode_version_conn(@db, key, version), encoded, CheckpointPublicationPhase.parse(phase), error)
    end

    def checkpoint_publications : Array(CheckpointPublication)
      publications = [] of CheckpointPublication
      @db.query("SELECT id, history_key, version, phase, encoded, last_error FROM history_checkpoint_publications ORDER BY id") do |rs|
        rs.each do
          id = rs.read(String)
          key = rs.read(Int64)
          version = rs.read(String)
          phase = rs.read(String)
          encoded = rs.read(String)
          error = rs.read(String?)
          publications << CheckpointPublication.new(id, history_for_key(key), decode_version_conn(@db, key, version), encoded, CheckpointPublicationPhase.parse(phase), error)
        end
      end
      publications
    end

    def insert_replication_outbox(entry : ReplicationOutboxEntry) : Nil
      @db.transaction do |tx|
        conn = tx.connection
        key = history_conn(conn, entry.pack.history_id)
        conn.exec(
          "INSERT OR REPLACE INTO history_replication_outbox (id, history_key, pack, state, last_error) VALUES (?, ?, ?, ?, ?)",
          entry.id, key, ReplicationPackCodec.encode(entry.pack), entry.state.to_s, entry.last_error,
        )
      end
    end

    def replication_outbox_entries(state : ReplicationOutboxState? = nil) : Array(ReplicationOutboxEntry)
      entries = [] of ReplicationOutboxEntry
      if state
        @db.query("SELECT pack, state, last_error FROM history_replication_outbox WHERE state = ? ORDER BY id", state.to_s) do |rs|
          rs.each { entries << outbox_entry(rs) }
        end
      else
        @db.query("SELECT pack, state, last_error FROM history_replication_outbox ORDER BY id") do |rs|
          rs.each { entries << outbox_entry(rs) }
        end
      end
      entries
    end

    def replication_outbox_size : Int32
      @db.scalar("SELECT COUNT(*) FROM history_replication_outbox WHERE state IN ('Pending', 'Sending')").as(Int64).to_i32
    end

    def update_replication_outbox_state(id : String, state : ReplicationOutboxState, error : String? = nil) : Nil
      @db.exec("UPDATE history_replication_outbox SET state = ?, last_error = ? WHERE id = ?", state.to_s, error, id)
    end

    def upsert_history_connection_state(state : HistoryConnectionState) : Nil
      @db.transaction do |tx|
        conn = tx.connection
        key = history_conn(conn, state.history_id)
        local, _ = version_row_conn(conn, key, state.local_version)
        remote, _ = version_row_conn(conn, key, state.remote_version)
        conn.exec(
          "INSERT OR REPLACE INTO history_connection_states (history_key, local_version, remote_version, reset_generation, status, last_error) VALUES (?, ?, ?, ?, ?, ?)",
          key, local, remote, state.reset_generation.to_i64, state.status.to_s, state.last_error,
        )
      end
    end

    def load_history_connection_state(history : HistoryId) : HistoryConnectionState?
      key = @db.query_one?("SELECT history_key FROM histories WHERE history_uuid = ?", history.value.bytes.to_slice) do |rs|
        rs.read(Int64)
      end
      return nil unless key
      row = @db.query_one?("SELECT local_version, remote_version, reset_generation, status, last_error FROM history_connection_states WHERE history_key = ?", key) do |rs|
        {rs.read(String), rs.read(String), rs.read(Int64), rs.read(String), rs.read(String?)}
      end
      return nil unless row
      local, remote, generation, status, error = row
      HistoryConnectionState.new(
        history,
        decode_version_conn(@db, key, local),
        decode_version_conn(@db, key, remote),
        generation.to_u32,
        HistoryConnectionStatus.parse(status),
        error,
      )
    end

    private def outbox_entry(rs : DB::ResultSet) : ReplicationOutboxEntry
      ReplicationOutboxEntry.new(ReplicationPackCodec.decode(rs.read(String)), ReplicationOutboxState.parse(rs.read(String)), rs.read(String?))
    end

    private def history_for_key(key : Int64) : HistoryId
      uuid = @db.query_one("SELECT history_uuid FROM histories WHERE history_key = ?", key) do |rs|
        rs.read(Bytes)
      end
      HistoryId.new(UUID.new(uuid))
    end
  end
end
