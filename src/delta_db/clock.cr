module DeltaDB
  # A unique identifier for each distributed node (replica).
  #
  # Port of `crates/clock/src/clock.rs` `ReplicaId`.
  struct ReplicaId
    include Comparable(ReplicaId)

    getter value : UInt16

    LOCAL         = ReplicaId.new(0u16)
    REMOTE_SERVER = ReplicaId.new(1u16)
    AGENT         = ReplicaId.new(2u16)
    LOCAL_BRANCH  = ReplicaId.new(3u16)
    # First collaborative replica id; any id >= this is a collaborative replica.
    FIRST_COLLAB_ID = ReplicaId.new(8u16)

    def initialize(@value : UInt16)
    end

    def <=>(other : ReplicaId) : Int32
      @value <=> other.value
    end

    def remote? : Bool
      self == REMOTE_SERVER || self >= FIRST_COLLAB_ID
    end

    def to_s(io : IO) : Nil
      case self
      when LOCAL         then io << "<local>"
      when REMOTE_SERVER then io << "<remote>"
      when AGENT         then io << "<agent>"
      when LOCAL_BRANCH  then io << "<branch>"
      else                    io << @value
      end
    end
  end

  # A Lamport sequence number.
  alias Seq = UInt32

  # A Lamport timestamp: (sequence value, replica id).
  #
  # Port of `crates/clock/src/clock.rs` `Lamport`.
  struct Lamport
    include Comparable(Lamport)

    getter value : Seq
    getter replica_id : ReplicaId

    MIN = Lamport.new(ReplicaId.new(0u16), 0u32)
    MAX = Lamport.new(ReplicaId.new(UInt16::MAX), UInt32::MAX)

    def initialize(@replica_id : ReplicaId, @value : Seq)
    end

    def self.new(replica_id : ReplicaId) : Lamport
      Lamport.new(replica_id, 1u32)
    end

    def <=>(other : Lamport) : Int32
      r = @value <=> other.value
      r == 0 ? @replica_id <=> other.replica_id : r
    end

    # Pack into a u64: value in the high 32 bits, replica id in the low 16.
    def as_u64 : UInt64
      (@value.to_u64 << 32) | @replica_id.value.to_u64
    end
  end

  # A mutable Lamport clock.
  #
  # Corresponds to `deltadb::delta::Clock`.
  class Clock
    getter lamport : Lamport

    def initialize(@lamport : Lamport = Lamport.new(ReplicaId::LOCAL))
    end

    # Return the current timestamp and advance the clock.
    def tick : Lamport
      old = @lamport
      @lamport = Lamport.new(@lamport.replica_id, @lamport.value + 1)
      old
    end

    # Advance past `timestamp`.
    def observe(timestamp : Lamport) : Nil
      @lamport = Lamport.new(@lamport.replica_id, Math.max(@lamport.value, timestamp.value) + 1)
    end
  end

  # A version vector of Lamport timestamps, indexed by replica id.
  #
  # Port of `crates/clock/src/clock.rs` `Global`.
  class Global
    def initialize(@values : Array(UInt32) = [] of UInt32)
    end

    def deep_clone : Global
      Global.new(@values.dup)
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

    def join(other : Global) : Nil
      if other.@values.size > @values.size
        @values.concat(Array(UInt32).new(other.@values.size - @values.size, 0u32))
      end
      other.@values.each_with_index do |v, i|
        @values[i] = Math.max(@values[i], v)
      end
    end

    def meet(other : Global) : Nil
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

    def observed_any?(other : Global) : Bool
      other.@values.each_with_index.any? do |right, i|
        right > 0 && (@values[i]? || 0u32) >= right
      end
    end

    def observed_all?(other : Global) : Bool
      return false if @values.size < other.@values.size
      other.@values.each_with_index.all? do |right, i|
        @values[i] >= right
      end
    end

    def changed_since?(other : Global) : Bool
      return true if @values.size > other.@values.size
      @values.each_with_index.any? do |left, i|
        left > (other.@values[i]? || 0u32)
      end
    end

    # The most recent timestamp observed, if any.
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
      io << "Global{"
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
