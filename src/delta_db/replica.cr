# src/delta_db/replica.cr
module DeltaDB
  class Replica(T)
    getter actor_id : ReplicaId
    getter clock : Clock
    getter value : T
    property history : History::Dag
    getter seal_state : SealState

    def initialize(@value : T, @actor_id : ReplicaId = ReplicaId::LOCAL, @clock : Clock = Clock.new, history_id : HistoryId = HistoryId.random)
      @history = History::Dag.new(history_id)
      @seal_state = SealState.new
      @outgoing = [] of History::Batch
    end

    def tick : Lamport
      @clock.tick
    end

    def apply_history_delta(delta : Delta) : History::Batch
      @seal_state.ensure_mutable!
      batch = apply_delta(delta)
      @outgoing << batch
      batch
    end

    def apply_history_delta_batch(batch : History::Batch) : Nil
      @seal_state.ensure_mutable!
      batch.deltas.each { |delta| apply_delta(delta) }
    end

    def outgoing_history_deltas : Array(Delta)
      @outgoing.flat_map(&.deltas)
    end

    def drain_confirmed_outgoing : Array(History::Batch)
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

    private def apply_delta(delta : Delta) : History::Batch
      DeltaApplication.apply(@value, delta)
      parents = @history.timelines[delta.timeline]?.try(&.head) || HistoryVersion.new
      id = DeltaBatchId.new(delta.timeline.uuid, delta.timestamp.value.to_u64)
      batch = History::Batch.new(id, delta.timeline, delta.actor, parents, [delta])
      @history.insert_on_timeline(batch)
      if delta.operation.try(&.kind) == ClientOperationKind::Seal
        @seal_state.seal(@history.timeline_version)
      end
      batch
    end
  end
end
