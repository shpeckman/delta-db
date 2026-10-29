# src/delta_db/history/epoch.cr
module DeltaDB
  module History
    struct Epoch
      getter epoch : UInt64
      getter start_version : HistoryVersion

      def initialize(@epoch : UInt64, @start_version : HistoryVersion)
      end
    end
  end
end
