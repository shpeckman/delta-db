# src/delta_db/history/record.cr
module DeltaDB
  module History
    struct Record
      getter history_id : HistoryId
      getter timeline_id : TimelineId
      getter target_version : Version

      def initialize(@history_id : HistoryId, @timeline_id : TimelineId, @target_version : Version)
      end
    end
  end
end
