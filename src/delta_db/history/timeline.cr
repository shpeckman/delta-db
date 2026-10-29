# src/delta_db/history/timeline.cr
module DeltaDB
  module History
    struct Timeline
      getter id : TimelineId
      getter head : Version
      getter origin : Version
      getter parent : TimelineId?
      getter reset_generation : UInt32

      def initialize(
        @id : TimelineId,
        @head : Version = Version.new,
        @origin : Version = Version.new,
        @parent : TimelineId? = nil,
        @reset_generation : UInt32 = id.generation,
      )
      end

      def with_head(head : Version) : Timeline
        Timeline.new(@id, head, @origin, @parent, @reset_generation)
      end
    end
  end
end
