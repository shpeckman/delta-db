# src/delta_db/replication/connection.cr
module DeltaDB
  module Replication
    class Connection
      enum Status
        Offline
        Syncing
        Synced
        Error
      end

      getter history_id : HistoryId
      property local_version : HistoryVersion
      property remote_version : HistoryVersion
      property reset_generation : UInt32
      property status : HistoryConnectionStatus
      property last_error : String?

      def initialize(
        @history_id : HistoryId,
        @local_version : HistoryVersion = HistoryVersion.new,
        @remote_version : HistoryVersion = HistoryVersion.new,
        @reset_generation : UInt32 = 0u32,
        @status : HistoryConnectionStatus = HistoryConnectionStatus::Offline,
        @last_error : String? = nil,
      )
      end
    end
  end
end
