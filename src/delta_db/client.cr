# src/delta_db/client.cr
module DeltaDB
  class Client
    getter store : Repository::Store

    def initialize
      @store = Repository::Store.new
      @outgoing = [] of History::Batch
    end

    def new_history_id : HistoryId
      HistoryId.random
    end

    def new_local_repository_id : LocalRepositoryId
      LocalRepositoryId.random
    end

    def create_repository(local_id : LocalRepositoryId = new_local_repository_id, remote_id : RemoteRepositoryId? = nil, blob_store : Blob::Store = Blob::Store.new) : Repository
      repository = @store.create(local_id, remote_id, new_history_id, blob_store)
      repository
    end

    def open_repository(id : LocalRepositoryId) : Repository
      @store.get(id) || raise NotFoundError.new("missing repository: #{id}")
    end

    def open_shared_repository(remote_id : RemoteRepositoryId, blob_store : Blob::Store = Blob::Store.new) : Repository
      @store.open_shared(remote_id, blob_store: blob_store)
    end

    def apply_history_delta(repository : Repository, delta : Delta) : History::Batch
      batch = repository.apply(delta)
      @outgoing << batch
      batch
    end

    def apply_history_delta_batch(repository : Repository, batch : History::Batch) : Nil
      repository.apply_remote(batch)
    end

    def outgoing_history_deltas : Array(Delta)
      @outgoing.flat_map(&.deltas)
    end

    def outgoing_history_delta_count : Int32
      @outgoing.sum(&.deltas.size)
    end

    def outgoing_history_queue_is_empty? : Bool
      @outgoing.empty?
    end

    def drain_confirmed_outgoing : Array(History::Batch)
      confirmed = @outgoing.dup
      @outgoing.clear
      confirmed
    end

    def save(storage : Storage) : Nil
      @store.save(storage)
    end
  end
end
