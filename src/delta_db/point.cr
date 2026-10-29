# src/delta_db/point.cr
module DeltaDB
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
