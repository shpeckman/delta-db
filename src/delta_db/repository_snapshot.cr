# src/delta_db/repository_snapshot.cr
module DeltaDB
  class RepositorySnapshot
    getter local_id : LocalRepositoryId
    getter remote_id : RemoteRepositoryId?
    getter history : History::Snapshot
    getter entries : Hash(String, MapEntry)
    getter blobs : Hash(String, Bytes)
    getter sealed_version : HistoryVersion?

    def initialize(
      @local_id : LocalRepositoryId,
      @remote_id : RemoteRepositoryId?,
      @history : History::Snapshot,
      @entries : Hash(String, MapEntry),
      @blobs : Hash(String, Bytes),
      @sealed_version : HistoryVersion? = nil,
    )
    end
  end
end
