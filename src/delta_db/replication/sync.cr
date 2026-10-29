# src/delta_db/replication/sync.cr
module DeltaDB
  module Replication
    class Sync
      getter outbox : Outbox

      def initialize(@storage : Storage, @remote : Peer)
        @outbox = Outbox.new(@storage)
        @states = {} of HistoryId => Connection
      end

      def push_history(dag : History::Dag) : Connection
        state = connection_state(dag.history_id)
        state.status = Connection::Status::Syncing
        save_state(state)
        pack = Pack.from(dag, state.remote_version)
        entry = @outbox.append(pack)
        begin
          @remote.install_pack(pack)
          @outbox.acknowledge(entry.id)
          state.local_version = dag.timeline_version
          state.remote_version = @remote.history(dag.history_id).timeline_version
          state.status = Connection::Status::Synced
          state.last_error = nil
        rescue error
          @outbox.fail(entry.id, error.message || error.class.name)
          fail_history(dag.history_id, error)
          raise error
        end
        save_state(state)
        state
      end

      def pull_history(dag : History::Dag) : Connection
        state = connection_state(dag.history_id)
        pack = @remote.pack_for_history(dag.history_id, state.local_version)
        dag.merge_checkpoint(pack.snapshot)
        state.local_version = dag.timeline_version
        state.remote_version = @remote.history(dag.history_id).timeline_version
        state.status = Connection::Status::Synced
        state.last_error = nil
        save_state(state)
        state
      end

      def sync_history(dag : History::Dag) : Connection
        push_history(dag)
        pull_history(dag)
      end

      def retry_history(dag : History::Dag) : Connection
        state = connection_state(dag.history_id)
        state.status = Connection::Status::Syncing
        state.last_error = nil
        save_state(state)
        sync_history(dag)
      rescue error
        fail_history(dag.history_id, error)
        raise error
      end

      def reset_local_timeline(dag : History::Dag, timeline : TimelineId, origin : History::Version) : TimelineId
        reset = dag.reset_timeline(timeline, origin)
        @remote.reset_timeline(dag.history_id, timeline, origin)
        state = connection_state(dag.history_id)
        state.reset_generation = reset.generation
        save_state(state)
        sync_history(dag)
        reset
      end

      def fork_remote_timeline(dag : History::Dag, source : TimelineId, target : TimelineId) : History::Timeline
        forked = @remote.fork_timeline(dag.history_id, source, target)
        pull_history(dag)
        dag.timelines[target]
      end

      def connection_state(history_id : HistoryId) : Connection
        @states[history_id] ||= @storage.load_history_connection_state(history_id) || Connection.new(history_id)
      end

      private def save_state(state : Connection) : Nil
        @states[state.history_id] = state
        @storage.upsert_history_connection_state(state)
      end

      private def fail_history(history_id : HistoryId, error : Exception) : Nil
        state = connection_state(history_id)
        state.status = Connection::Status::Error
        state.last_error = error.message || error.class.name
        save_state(state)
      end
    end
  end
end
