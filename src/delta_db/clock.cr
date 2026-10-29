# src/delta_db/clock.cr
module DeltaDB
  class Clock
    getter lamport : Lamport

    def initialize(@lamport : Lamport = Lamport.new(ReplicaId::LOCAL))
    end

    def tick : Lamport
      old = @lamport
      @lamport = Lamport.new(@lamport.replica_id, @lamport.value + 1)
      old
    end

    def observe(timestamp : Lamport) : Nil
      @lamport = Lamport.new(@lamport.replica_id, Math.max(@lamport.value, timestamp.value) + 1)
    end
  end
end
