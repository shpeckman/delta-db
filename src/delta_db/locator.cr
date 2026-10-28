module DeltaDB
  # An identifier for a position in an ordered collection, supporting efficient
  # insertion before/after without renumbering (fractional indexing).
  #
  # Port of `crates/text/src/locator.rs`. The initial location is
  # `between(min, max)`, leaving room on both sides; sequential forward appends
  # stay at depth 1 because `between` biases `mid` just above `lhs`.
  struct Locator
    include Comparable(Locator)

    getter values : Array(UInt64)

    def initialize(@values : Array(UInt64) = [0u64])
    end

    def self.min : Locator
      Locator.new([0u64])
    end

    def self.max : Locator
      Locator.new([UInt64::MAX])
    end

    # Lexicographic comparison: element-wise, then shorter < longer on equal prefix.
    def <=>(other : Locator) : Int32
      a = @values
      b = other.values
      n = Math.min(a.size, b.size)
      (0...n).each do |i|
        c = a[i] <=> b[i]
        return c if c != 0
      end
      a.size <=> b.size
    end

    # A locator strictly between `lhs` and `rhs`.
    def self.between(lhs : Locator, rhs : Locator) : Locator
      unless lhs < rhs
        raise ArgumentError.new("locator bounds are not ordered: #{lhs.values} before #{rhs.values}")
      end

      values = [] of UInt64
      i = 0
      loop do
        l = i < lhs.values.size ? lhs.values[i] : 0u64
        r = i < rhs.values.size ? rhs.values[i] : UInt64::MAX
        # `>> 48` keeps the midpoint just above `lhs`, optimizing sequential typing.
        mid = l + ((r - l) >> 48)
        values << mid
        break if mid > l
        i += 1
      end
      Locator.new(values)
    end

    def size : Int32
      @values.size
    end

    def empty? : Bool
      @values.empty?
    end
  end
end
