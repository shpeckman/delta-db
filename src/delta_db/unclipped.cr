# src/delta_db/unclipped.cr
module DeltaDB
  struct Unclipped(T)
    getter value : T

    def initialize(@value : T)
    end

    def +(other : Unclipped(T)) : Unclipped(T)
      Unclipped(T).new(@value + other.value)
    end

    def -(other : Unclipped(T)) : Unclipped(T)
      Unclipped(T).new(@value - other.value)
    end
  end
end
