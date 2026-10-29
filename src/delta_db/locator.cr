# src/delta_db/locator.cr
module DeltaDB
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

    def self.between(lhs : Locator, rhs : Locator) : Locator
      unless lhs < rhs
        raise ArgumentError.new("locator bounds are not ordered: #{lhs.values} before #{rhs.values}")
      end

      values = [] of UInt64
      i = 0
      loop do
        l = i < lhs.values.size ? lhs.values[i] : 0u64
        r = i < rhs.values.size ? rhs.values[i] : UInt64::MAX
        mid = l + ((r > l ? r - l : 0u64) >> 48)
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
