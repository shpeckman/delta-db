module DeltaDB
  # A wrapper that lifts a value to "unclipped" coordinates for the rope's
  # seek/clip operations. Plain generic wrapper here; the `Dimension` wiring
  # arrives with the `SumTree` port.
  #
  # Port of `crates/rope/src/unclipped.rs`.
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
