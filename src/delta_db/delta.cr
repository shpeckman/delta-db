# src/delta_db/delta.cr
module DeltaDB
  struct Delta
    getter history : HistoryId
    getter timeline : TimelineId
    getter actor : ActorUuid
    getter timestamp : Lamport
    getter value : Bytes
    getter operation : ClientOperation?

    def initialize(
      @history : HistoryId,
      @timeline : TimelineId,
      @actor : ActorUuid,
      @timestamp : Lamport,
      @value : Bytes,
      @operation : ClientOperation? = nil,
    )
    end
  end
end
