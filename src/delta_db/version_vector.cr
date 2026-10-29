# src/delta_db/version_vector.cr
module DeltaDB
  class VersionVector
    def initialize(@values : Array(UInt32) = [] of UInt32)
    end

    def clone : VersionVector
      VersionVector.new(@values.dup)
    end

    def get(replica_id : ReplicaId) : UInt32
      @values[replica_id.value.to_i32]? || 0u32
    end

    def observe(timestamp : Lamport) : Nil
      return if timestamp.value == 0
      i = timestamp.replica_id.value.to_i32
      while @values.size <= i
        @values << 0u32
      end
      @values[i] = Math.max(@values[i], timestamp.value)
    end

    def join(other : VersionVector) : Nil
      if other.@values.size > @values.size
        @values.concat(Array(UInt32).new(other.@values.size - @values.size, 0u32))
      end
      other.@values.each_with_index do |v, i|
        @values[i] = Math.max(@values[i], v)
      end
    end

    def meet(other : VersionVector) : Nil
      if other.@values.size > @values.size
        @values.concat(Array(UInt32).new(other.@values.size - @values.size, 0u32))
      end
      new_len = 0
      other.@values.each_with_index do |right, i|
        left = @values[i]
        @values[i] = if left == 0
                       right
                     elsif right == 0
                       left
                     else
                       Math.min(left, right)
                     end
        new_len = i + 1 if @values[i] != 0
      end
      @values.truncate(new_len) if other.@values.size == @values.size
    end

    def observed?(timestamp : Lamport) : Bool
      get(timestamp.replica_id) >= timestamp.value
    end

    def observed_any?(other : VersionVector) : Bool
      other.@values.each_with_index.any? do |right, i|
        right > 0 && (@values[i]? || 0u32) >= right
      end
    end

    def observed_all?(other : VersionVector) : Bool
      return false if @values.size < other.@values.size
      other.@values.each_with_index.all? do |right, i|
        @values[i] >= right
      end
    end

    def changed_since?(other : VersionVector) : Bool
      return true if @values.size > other.@values.size
      @values.each_with_index.any? do |left, i|
        left > (other.@values[i]? || 0u32)
      end
    end

    def most_recent : Lamport?
      best : Lamport? = nil
      @values.each_with_index do |v, i|
        next if v == 0
        ts = Lamport.new(ReplicaId.new(i.to_u16), v)
        if best.nil? || ts.value > best.not_nil!.value
          best = ts
        end
      end
      best
    end

    def to_s(io : IO) : Nil
      io << "VersionVector{"
      first = true
      @values.each_with_index do |v, i|
        next if v == 0
        io << ", " unless first
        first = false
        io << ReplicaId.new(i.to_u16) << ": " << v
      end
      io << "}"
    end
  end
end
