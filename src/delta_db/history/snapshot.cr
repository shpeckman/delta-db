# src/delta_db/history/snapshot.cr
module DeltaDB
  module History
    struct Snapshot
      getter history_id : HistoryId
      getter batches : Array(Batch)
      getter timelines : Array(Timeline)
      getter epochs : Array(Epoch)
      getter max_timestamp : UInt64
      getter epoch_count : UInt64

      def initialize(
        @history_id : HistoryId,
        @batches : Array(Batch) = [] of Batch,
        @timelines : Array(Timeline) = [] of Timeline,
        @epochs : Array(Epoch) = [] of Epoch,
        @max_timestamp : UInt64 = 0u64,
        @epoch_count : UInt64 = 0u64,
      )
      end
    end
  end
end
