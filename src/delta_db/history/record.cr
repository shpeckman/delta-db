# src/delta_db/history/record.cr
module DeltaDB
  module History
    struct Record
      getter history_id : HistoryId
      getter timeline_id : TimelineId
      getter target_version : HistoryVersion

      def initialize(@history_id : HistoryId, @timeline_id : TimelineId, @target_version : HistoryVersion)
      end
    end
  end
end
