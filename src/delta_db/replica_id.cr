# src/delta_db/replica_id.cr
module DeltaDB
  struct ReplicaId
    include Comparable(ReplicaId)

    getter value : UInt16

    LOCAL           = ReplicaId.new(0u16)
    REMOTE_SERVER   = ReplicaId.new(1u16)
    AGENT           = ReplicaId.new(2u16)
    LOCAL_BRANCH    = ReplicaId.new(3u16)
    FIRST_COLLAB_ID = ReplicaId.new(8u16)

    def initialize(@value : UInt16)
    end

    def <=>(other : ReplicaId) : Int32
      @value <=> other.value
    end

    def remote? : Bool
      self == REMOTE_SERVER || self >= FIRST_COLLAB_ID
    end

    def to_s(io : IO) : Nil
      case self
      when LOCAL         then io << "<local>"
      when REMOTE_SERVER then io << "<remote>"
      when AGENT         then io << "<agent>"
      when LOCAL_BRANCH  then io << "<branch>"
      else                    io << @value
      end
    end
  end
end
