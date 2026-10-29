# src/delta_db/repository_snapshot.cr
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
end
