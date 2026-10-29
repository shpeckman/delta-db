# src/delta_db/history/batch.cr
module DeltaDB
  module History
    struct Batch
      getter id : DeltaBatchId
      getter timeline : TimelineId
      getter actor : ActorUuid
      getter parents : HistoryVersion
      getter deltas : Array(Delta)
      getter epoch : UInt64

      def initialize(
        @id : DeltaBatchId,
        @timeline : TimelineId,
        @actor : ActorUuid,
        @parents : HistoryVersion = HistoryVersion.new,
        @deltas : Array(Delta) = [] of Delta,
        @epoch : UInt64 = 0u64,
      )
      end

      def causal_parent : HistoryVersion
        @parents
      end
    end
  end
end
