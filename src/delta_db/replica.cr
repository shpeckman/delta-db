# src/delta_db/replica.cr
module DeltaDB
  class Replica(T)
    getter actor_id : ReplicaId
    getter clock : Clock
    getter value : T
    property history : HistoryDag
    getter seal_state : SealState

    def initialize(@value : T, @actor_id : ReplicaId = ReplicaId::LOCAL, @clock : Clock = Clock.new, history_id : HistoryId = HistoryId.random)
      @history = HistoryDag.new(history_id)
      @seal_state = SealState.new
      @outgoing = [] of HistoryDeltaBatch
    end

    def tick : Lamport
      @clock.tick
    end

    def apply_history_delta(delta : Delta) : HistoryDeltaBatch
      @seal_state.ensure_mutable!
      batch = apply_delta(delta)
      @outgoing << batch
      batch
    end

    def apply_history_delta_batch(batch : HistoryDeltaBatch) : Nil
      @seal_state.ensure_mutable!
      batch.deltas.each { |delta| apply_delta(delta) }
    end

    def outgoing_history_deltas : Array(Delta)
      @outgoing.flat_map(&.deltas)
    end

    def drain_confirmed_outgoing : Array(HistoryDeltaBatch)
      confirmed = @outgoing.dup
      @outgoing.clear
      confirmed
    end

    def seal : Nil
      @seal_state.seal(@history.timeline_version)
    end

    def sealed? : Bool
      @seal_state.sealed?
    end

    private def apply_delta(delta : Delta) : HistoryDeltaBatch
      DeltaApplication.apply(@value, delta)
      parents = @history.timelines[delta.timeline]?.try(&.head) || HistoryVersion.new
      id = DeltaBatchId.new(delta.timeline.uuid, delta.timestamp.value.to_u64)
      batch = HistoryDeltaBatch.new(id, delta.timeline, delta.actor, parents, [delta])
      @history.insert_on_timeline(batch)
      if delta.operation.try(&.kind) == ClientOperationKind::Seal
        @seal_state.seal(@history.timeline_version)
      end
      batch
    end
  end
end
