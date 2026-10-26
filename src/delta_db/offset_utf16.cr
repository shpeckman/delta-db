module DeltaDB
  # A byte offset measured in UTF-16 code units.
  #
  # Port of `crates/rope/src/offset_utf16.rs`. Rust uses `usize`; we use `UInt64`
  # to match 64-bit `usize`.
  struct OffsetUtf16
    include Comparable(OffsetUtf16)

    getter value : UInt64

    def initialize(@value : UInt64 = 0u64)
    end

    def self.zero : OffsetUtf16
      OffsetUtf16.new
    end

    def zero? : Bool
      @value == 0
    end

    def <=>(other : OffsetUtf16) : Int32
      @value <=> other.value
    end

    def +(other : OffsetUtf16) : OffsetUtf16
      OffsetUtf16.new(@value + other.value)
    end

    def -(other : OffsetUtf16) : OffsetUtf16
      OffsetUtf16.new(@value - other.value)
    end

    def to_s(io : IO) : Nil
      io << @value
    end

    def inspect(io : IO) : Nil
      io << "OffsetUtf16(" << @value << ')'
    end
  end
end
