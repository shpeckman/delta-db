# src/delta_db/history/snapshot.cr
module DeltaDB
  module History
    struct Snapshot
      getter history_id : HistoryId
      getter batches : Array(HistoryDeltaBatch)
      getter timelines : Array(HistoryTimeline)
      getter epochs : Array(HistoryEpoch)
      getter max_timestamp : UInt64
      getter epoch_count : UInt64

      def initialize(
        @history_id : HistoryId,
        @batches : Array(HistoryDeltaBatch) = [] of HistoryDeltaBatch,
        @timelines : Array(HistoryTimeline) = [] of HistoryTimeline,
        @epochs : Array(HistoryEpoch) = [] of HistoryEpoch,
        @max_timestamp : UInt64 = 0u64,
        @epoch_count : UInt64 = 0u64,
      )
      end
    end
  end
end
