# src/delta_db/repository.cr
module DeltaDB
  class RepositorySnapshot
    getter local_id : LocalRepositoryId
    getter remote_id : RemoteRepositoryId?
    getter history : HistoryDagSnapshot
    getter entries : Hash(String, MapEntry)
    getter blobs : Hash(String, Bytes)
    getter sealed_version : HistoryVersion?

    def initialize(
      @local_id : LocalRepositoryId,
      @remote_id : RemoteRepositoryId?,
      @history : HistoryDagSnapshot,
      @entries : Hash(String, MapEntry),
      @blobs : Hash(String, Bytes),
      @sealed_version : HistoryVersion? = nil,
    )
    end
  end

  class Repository
    getter local_id : LocalRepositoryId
    getter remote_id : RemoteRepositoryId?
    getter replica : Replica(Map)
    getter blob_store : BlobStore

    def initialize(@local_id : LocalRepositoryId, @remote_id : RemoteRepositoryId? = nil, history_id : HistoryId = HistoryId.random)
      @replica = Replica(Map).new(Map.new, history_id: history_id)
      @blob_store = BlobStore.new
    end

    def history : HistoryDag
      @replica.history
    end

    def map : Map
      @replica.value
    end

    def apply(delta : Delta) : HistoryDeltaBatch
      @replica.apply_history_delta(delta)
    end

    def apply_remote(batch : HistoryDeltaBatch) : Nil
      @replica.apply_history_delta_batch(batch)
    end

    def snapshot : RepositorySnapshot
      RepositorySnapshot.new(
        @local_id,
        @remote_id,
        history.checkpoint,
        map.entries.dup,
        @blob_store.snapshot,
        @replica.seal_state.history_version,
      )
    end

    def self.from_snapshot(snapshot : RepositorySnapshot) : Repository
      repository = Repository.new(snapshot.local_id, snapshot.remote_id, snapshot.history.history_id)
      repository.replica.history = HistoryDag.from_snapshot(snapshot.history)
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

  class RepositoryStore
    getter repositories : Hash(LocalRepositoryId, Repository)

    def initialize
      @repositories = {} of LocalRepositoryId => Repository
      @remote_index = {} of RemoteRepositoryId => LocalRepositoryId
    end

    def create(local_id : LocalRepositoryId = LocalRepositoryId.random, remote_id : RemoteRepositoryId? = nil, history_id : HistoryId = HistoryId.random) : Repository
      if @repositories.has_key?(local_id)
        raise ArgumentError.new("repository already exists: #{local_id}")
      end
      repository = Repository.new(local_id, remote_id, history_id)
      @repositories[local_id] = repository
      @remote_index[remote_id] = local_id if remote_id
      repository
    end

    def get(id : LocalRepositoryId) : Repository?
      @repositories[id]?
    end

    def open_shared(remote_id : RemoteRepositoryId, local_id : LocalRepositoryId = LocalRepositoryId.random) : Repository
      if existing = @remote_index[remote_id]?
        return @repositories[existing]
      end
      create(local_id, remote_id, HistoryId.new(remote_id.value))
    end

    def remove(id : LocalRepositoryId) : Repository?
      repository = @repositories.delete(id)
      if repository && (remote_id = repository.remote_id)
        @remote_index.delete(remote_id)
      end
      repository
    end

    def save(storage : Storage) : Nil
      @repositories.each_value { |repository| repository.save(storage) }
    end

    def restore(snapshots : Array(RepositorySnapshot)) : Nil
      @repositories.clear
      @remote_index.clear
      snapshots.each do |snapshot|
        repository = Repository.from_snapshot(snapshot)
        @repositories[repository.local_id] = repository
        if remote_id = repository.remote_id
          @remote_index[remote_id] = repository.local_id
        end
      end
    end
  end

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
