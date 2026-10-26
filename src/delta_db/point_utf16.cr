module DeltaDB
  # A zero-indexed point in a text buffer measured in UTF-16 code units.
  #
  # Port of `crates/rope/src/point_utf16.rs`.
  struct PointUtf16
    include Comparable(PointUtf16)

    getter row : UInt32
    getter column : UInt32

    MAX = PointUtf16.new(UInt32::MAX, UInt32::MAX)

    def initialize(@row : UInt32 = 0u32, @column : UInt32 = 0u32)
    end

    def self.zero : PointUtf16
      PointUtf16.new
    end

    def zero? : Bool
      @row == 0 && @column == 0
    end

    def <=>(other : PointUtf16) : Int32
      r = @row <=> other.row
      r == 0 ? @column <=> other.column : r
    end

    def +(other : PointUtf16) : PointUtf16
      if other.row == 0
        PointUtf16.new(@row, @column + other.column)
      else
        PointUtf16.new(@row + other.row, other.column)
      end
    end

    def -(other : PointUtf16) : PointUtf16
      if @row == other.row
        PointUtf16.new(0u32, @column - other.column)
      else
        PointUtf16.new(@row - other.row, @column)
      end
    end

    def saturating_sub(other : PointUtf16) : PointUtf16
      self < other ? PointUtf16.zero : self - other
    end

    def to_s(io : IO) : Nil
      io << "PointUtf16(" << @row << ':' << @column << ')'
    end

    def inspect(io : IO) : Nil
      to_s(io)
    end
  end
end
