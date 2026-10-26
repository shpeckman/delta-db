module DeltaDB
  # A zero-indexed point in a text buffer consisting of a row and column.
  #
  # Port of `crates/rope/src/point.rs`.
  struct Point
    include Comparable(Point)

    getter row : UInt32
    getter column : UInt32

    MAX = Point.new(UInt32::MAX, UInt32::MAX)

    def initialize(@row : UInt32 = 0u32, @column : UInt32 = 0u32)
    end

    def self.zero : Point
      Point.new
    end

    def zero? : Bool
      @row == 0 && @column == 0
    end

    def <=>(other : Point) : Int32
      r = @row <=> other.row
      r == 0 ? @column <=> other.column : r
    end

    # Point addition: appending a same-row point advances the column; otherwise
    # the result is `(row + other.row, other.column)`.
    def +(other : Point) : Point
      if other.row == 0
        Point.new(@row, @column + other.column)
      else
        Point.new(@row + other.row, other.column)
      end
    end

    def -(other : Point) : Point
      if @row == other.row
        Point.new(0u32, @column - other.column)
      else
        Point.new(@row - other.row, @column)
      end
    end

    def saturating_sub(other : Point) : Point
      self < other ? Point.zero : self - other
    end

    def to_s(io : IO) : Nil
      io << "Point(" << @row << ':' << @column << ')'
    end

    def inspect(io : IO) : Nil
      to_s(io)
    end
  end
end
