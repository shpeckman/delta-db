# src/delta_db/repository/snapshot.cr
module DeltaDB
  class Repository
    class Snapshot
      getter local_id : LocalRepositoryId
      getter remote_id : RemoteRepositoryId?
      getter history : History::Snapshot
      getter entries : Hash(String, Map::Entry)
      getter blobs : Hash(String, Bytes)
      getter sealed_version : HistoryVersion?

      def initialize(
        @local_id : LocalRepositoryId,
        @remote_id : RemoteRepositoryId?,
        @history : History::Snapshot,
        @entries : Hash(String, Map::Entry),
        @blobs : Hash(String, Bytes),
        @sealed_version : HistoryVersion? = nil,
      )
      end
    end
  end
end
