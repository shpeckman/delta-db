# src/delta_db/repository.cr
module DeltaDB
  class Repository
    getter local_id : LocalRepositoryId
    getter remote_id : RemoteRepositoryId?
    getter replica : Replica(Map)
    getter blob_store : Blob::Store

    def initialize(@local_id : LocalRepositoryId, @remote_id : RemoteRepositoryId? = nil, history_id : HistoryId = HistoryId.random)
      @replica = Replica(Map).new(Map.new, history_id: history_id)
      @blob_store = Blob::Store.new
    end

    def history : History::Dag
      @replica.history
    end

    def map : Map
      @replica.value
    end

    def apply(delta : Delta) : History::Batch
      @replica.apply_history_delta(delta)
    end

    def apply_remote(batch : History::Batch) : Nil
      @replica.apply_history_delta_batch(batch)
    end

    def snapshot : Snapshot
      Snapshot.new(
        @local_id,
        @remote_id,
        history.checkpoint,
        map.entries.dup,
        @blob_store.snapshot,
        @replica.seal_state.history_version,
      )
    end

    def self.from_snapshot(snapshot : Snapshot) : Repository
      repository = Repository.new(snapshot.local_id, snapshot.remote_id, snapshot.history.history_id)
      repository.replica.history = History::Dag.from_snapshot(snapshot.history)
      repository.map.restore(snapshot.entries)
      repository.blob_store.restore(snapshot.blobs)
      if version = snapshot.sealed_version
        repository.replica.seal_state.seal(version)
      end
      repository
    end

    def save(storage : Storage) : Nil
      storage.save_dag(history)
    end
  end
end
