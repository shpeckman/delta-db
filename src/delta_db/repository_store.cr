# src/delta_db/repository_store.cr
module DeltaDB
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
end
