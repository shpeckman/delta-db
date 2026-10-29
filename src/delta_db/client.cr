# src/delta_db/client.cr
module DeltaDB
  class Client
    getter store : RepositoryStore

    def initialize
      @store = RepositoryStore.new
      @outgoing = [] of HistoryDeltaBatch
    end

    def new_history_id : HistoryId
      HistoryId.random
    end

    def new_local_repository_id : LocalRepositoryId
      LocalRepositoryId.random
    end

    def create_repository(local_id : LocalRepositoryId = new_local_repository_id, remote_id : RemoteRepositoryId? = nil) : Repository
      repository = @store.create(local_id, remote_id, new_history_id)
      repository
    end

    def open_repository(id : LocalRepositoryId) : Repository
      @store.get(id) || raise ArgumentError.new("missing repository: #{id}")
    end

    def open_shared_repository(remote_id : RemoteRepositoryId) : Repository
      @store.open_shared(remote_id)
    end

    def apply_history_delta(repository : Repository, delta : Delta) : HistoryDeltaBatch
      batch = repository.apply(delta)
      @outgoing << batch
      batch
    end

    def apply_history_delta_batch(repository : Repository, batch : HistoryDeltaBatch) : Nil
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

    def drain_confirmed_outgoing : Array(HistoryDeltaBatch)
      confirmed = @outgoing.dup
      @outgoing.clear
      confirmed
    end

    def save(storage : Storage) : Nil
      @store.save(storage)
    end
  end
end
