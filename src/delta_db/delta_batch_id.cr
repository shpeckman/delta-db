# src/delta_db/delta_batch_id.cr
require "uuid"

module DeltaDB
  struct DeltaBatchId
    include Comparable(DeltaBatchId)

    getter uuid : UUID
    getter ordinal : UInt64

    def initialize(@uuid : UUID, @ordinal : UInt64)
    end

    def <=>(other : DeltaBatchId) : Int32
      r = @uuid <=> other.uuid
      r == 0 ? @ordinal <=> other.ordinal : r
    end

    def to_s(io : IO) : Nil
      @uuid.to_s(io)
      io << '.' << @ordinal
    end
  end
end
