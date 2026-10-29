# src/delta_db/history/timeline.cr
module DeltaDB
  module History
    struct Timeline
      getter id : TimelineId
      property head : HistoryVersion
      getter origin : HistoryVersion
      getter parent : TimelineId?
      getter reset_generation : UInt32

      def initialize(
        @id : TimelineId,
        @head : HistoryVersion = HistoryVersion.new,
        @origin : HistoryVersion = HistoryVersion.new,
        @parent : TimelineId? = nil,
        @reset_generation : UInt32 = id.generation,
      )
      end
    end
  end
end
