# src/delta_db/lamport.cr
module DeltaDB
  struct Lamport
    alias Seq = UInt32

    include Comparable(Lamport)

    getter value : Seq
    getter replica_id : ReplicaId

    MIN = Lamport.new(ReplicaId.new(0u16), 0u32)
    MAX = Lamport.new(ReplicaId.new(UInt16::MAX), UInt32::MAX)

    def initialize(@replica_id : ReplicaId, @value : Seq)
    end

    def self.new(replica_id : ReplicaId) : Lamport
      Lamport.new(replica_id, 1u32)
    end

    def <=>(other : Lamport) : Int32
      r = @value <=> other.value
      r == 0 ? @replica_id <=> other.replica_id : r
    end

    def to_u64 : UInt64
      (@value.to_u64 << 32) | @replica_id.value.to_u64
    end
  end
end
