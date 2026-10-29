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
      property local_version : History::Version
      property remote_version : History::Version
      property reset_generation : UInt32
      property status : Status
      property last_error : String?

      def initialize(
        @history_id : HistoryId,
        @local_version : History::Version = History::Version.new,
        @remote_version : History::Version = History::Version.new,
        @reset_generation : UInt32 = 0u32,
        @status : Status = Status::Offline,
        @last_error : String? = nil,
      )
      end
    end
  end
end
