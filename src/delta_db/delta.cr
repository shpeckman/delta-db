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

  # A version within a history, wrapping a `DeltaBatchId`.
  #
  # Recovered from `deltadb::history::HistoryVersion`; stored as encoded text
  # (`encode_version_text`) in the `history_versions.version` column.
  struct HistoryVersion
    include Comparable(HistoryVersion)

    getter batch_id : DeltaBatchId

    def initialize(@batch_id : DeltaBatchId)
    end

    def <=>(other : HistoryVersion) : Int32
      @batch_id <=> other.batch_id
    end

    def to_s(io : IO) : Nil
      @batch_id.to_s(io)
    end
  end
end
