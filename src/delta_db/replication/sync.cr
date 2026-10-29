# src/delta_db/replication/sync.cr
module DeltaDB
  module Replication
    class Sync
      getter outbox : ReplicationOutbox

      def initialize(@storage : Storage, @remote : RemotePeer)
        @outbox = ReplicationOutbox.new(@storage)
        @states = {} of HistoryId => HistoryConnectionState
      end

      def push_history(dag : HistoryDag) : HistoryConnectionState
        state = connection_state(dag.history_id)
        state.status = HistoryConnectionStatus::Syncing
        save_state(state)
        pack = ReplicationPacker.pack(dag, state.remote_version)
        entry = @outbox.append(pack)
        begin
          @remote.install_pack(pack)
          @outbox.acknowledge(entry.id)
          state.local_version = dag.timeline_version
          state.remote_version = @remote.history(dag.history_id).timeline_version
          state.status = HistoryConnectionStatus::Synced
          state.last_error = nil
        rescue error
          @outbox.fail(entry.id, error.message || error.class.name)
          fail_history(dag.history_id, error)
          raise error
        end
        save_state(state)
        state
      end

      def pull_history(dag : HistoryDag) : HistoryConnectionState
        state = connection_state(dag.history_id)
        pack = @remote.pack_for_history(dag.history_id, state.local_version)
        dag.merge_checkpoint(pack.snapshot)
        state.local_version = dag.timeline_version
        state.remote_version = @remote.history(dag.history_id).timeline_version
        state.status = HistoryConnectionStatus::Synced
        state.last_error = nil
        save_state(state)
        state
      end

      def sync_history(dag : HistoryDag) : HistoryConnectionState
        push_history(dag)
        pull_history(dag)
      end

      def retry_history(dag : HistoryDag) : HistoryConnectionState
        state = connection_state(dag.history_id)
        state.status = HistoryConnectionStatus::Syncing
        state.last_error = nil
        save_state(state)
        sync_history(dag)
      rescue error
        fail_history(dag.history_id, error)
        raise error
      end

      def reset_local_timeline(dag : HistoryDag, timeline : TimelineId, origin : HistoryVersion) : TimelineId
        reset = dag.reset_timeline(timeline, origin)
        @remote.reset_timeline(dag.history_id, timeline, origin)
        state = connection_state(dag.history_id)
        state.reset_generation = reset.generation
        save_state(state)
        sync_history(dag)
        reset
      end

      def fork_remote_timeline(dag : HistoryDag, source : TimelineId, target : TimelineId) : HistoryTimeline
        forked = @remote.fork_timeline(dag.history_id, source, target)
        pull_history(dag)
        dag.timelines[target]
      end

      def connection_state(history_id : HistoryId) : HistoryConnectionState
        @states[history_id] ||= @storage.load_history_connection_state(history_id) || HistoryConnectionState.new(history_id)
      end

      private def save_state(state : HistoryConnectionState) : Nil
        @states[state.history_id] = state
        @storage.upsert_history_connection_state(state)
      end

      private def fail_history(history_id : HistoryId, error : Exception) : Nil
        state = connection_state(history_id)
        state.status = HistoryConnectionStatus::Error
        state.last_error = error.message || error.class.name
        save_state(state)
      end
    end
  end
end
