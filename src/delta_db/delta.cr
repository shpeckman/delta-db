# src/delta_db/delta.cr
require "uuid"

module DeltaDB
  # The core identity types of the delta/history engine.
  #
  # Recovered from `deltadb::delta` / `deltadb::history` symbols and validated
  # against the real database: UUID-backed newtypes, plus the composite
  # `TimelineId` (uuid + generation) and `DeltaBatchId` (uuid + ordinal), and
  # `HistoryVersion` (wraps a `DeltaBatchId`, stored as encoded text).

  macro uuid_id(name)
    struct {{name.id}}
      include Comparable({{name.id}})

      getter value : UUID

      def initialize(@value : UUID)
      end

      def self.random : {{name.id}}
        {{name.id}}.new(UUID.random)
      end

      def <=>(other : {{name.id}}) : Int32
        @value <=> other.value
      end

      def to_s(io : IO) : Nil
        @value.to_s(io)
      end
    end
  end

  # Identifies an actor (a replica participating in the CRDT).
  uuid_id ActorUuid

  # Identifies a local repository.
  uuid_id LocalRepositoryId

  # Identifies a remote (shared) repository.
  uuid_id RemoteRepositoryId

  # Identifies a history (a set of timelines).
  uuid_id HistoryId

  # Identifies a single delta.
  uuid_id DeltaId

  # Identifies a timeline: a UUID plus a reset generation.
  #
  # Observed in the runtime log as `TimelineId(UUID.N)`.
  struct TimelineId
    include Comparable(TimelineId)

    getter uuid : UUID
    getter generation : UInt32

    def initialize(@uuid : UUID, @generation : UInt32 = 0u32)
    end

    def self.random : TimelineId
      TimelineId.new(UUID.random)
    end

    def <=>(other : TimelineId) : Int32
      r = @uuid <=> other.uuid
      r == 0 ? @generation <=> other.generation : r
    end

    def to_s(io : IO) : Nil
      @uuid.to_s(io)
      io << '.' << @generation
    end
  end

  # Identifies a batch of deltas: a UUID plus a monotonic batch ordinal.
  #
  # Observed as `DeltaBatchId(UUID.N)`.
  struct DeltaBatchId
    include Comparable(DeltaBatchId)

    getter uuid : UUID
    getter ordinal : UInt64

    def initialize(@uuid : UUID, @ordinal : UInt64)
    end

    def <=>(other : DeltaBatchId) : Int32
      r = @uuid <=> other.uuid
      r == 0 ? @ordinal <=> other.ordinal : r
    end

    def to_s(io : IO) : Nil
      @uuid.to_s(io)
      io << '.' << @ordinal
    end
  end

  struct HistoryVersion
    getter ids : Array(DeltaBatchId)

    def initialize(ids : Enumerable(DeltaBatchId) = [] of DeltaBatchId)
      @ids = ids.to_a.sort.uniq
    end

    def self.from_id(id : DeltaBatchId) : HistoryVersion
      new([id])
    end

    def self.from_ids(ids : Enumerable(DeltaBatchId)) : HistoryVersion
      new(ids)
    end

    def self.decode_version_text(text : String, actors : Hash(Int64, TimelineId)) : HistoryVersion
      return new if text.empty?

      ids = text.split(',').map do |entry|
        parts = entry.split(':')
        unless parts.size == 2
          raise ArgumentError.new("invalid history version entry: #{entry.inspect}")
        end

        actor = parts[0].to_i64
        timeline = actors.fetch(actor) do
          raise ArgumentError.new("unknown actor ordinal: #{actor}")
        end
        DeltaBatchId.new(timeline.uuid, parts[1].to_u64)
      end
      new(ids)
    end

    def empty? : Bool
      @ids.empty?
    end

    def size : Int32
      @ids.size
    end

    def contains?(id : DeltaBatchId) : Bool
      @ids.includes?(id)
    end

    def observe(id : DeltaBatchId) : Nil
      return if contains?(id)

      @ids << id
      @ids.sort!
    end

    def union(other : HistoryVersion) : HistoryVersion
      HistoryVersion.new(@ids + other.ids)
    end

    def encode_version_text(actors : Hash(UUID, Int64)) : String
      @ids.map do |id|
        actor = actors.fetch(id.uuid) do
          raise ArgumentError.new("missing actor ordinal for timeline: #{id.uuid}")
        end
        "#{actor}:#{id.ordinal}"
      end.join(',')
    end

    def to_s(io : IO) : Nil
      @ids.join(io, ',', &.to_s(io))
    end
  end
end
