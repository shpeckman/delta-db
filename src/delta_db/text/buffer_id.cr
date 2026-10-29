# src/delta_db/text/buffer_id.cr
module DeltaDB
  module Text
    struct BufferId
      include Comparable(BufferId)

      getter value : UInt64

      def initialize(@value : UInt64)
      end

      def <=>(other : BufferId) : Int32
        @value <=> other.value
      end

      def to_s(io : IO) : Nil
        io << @value
      end
    end
  end
end
