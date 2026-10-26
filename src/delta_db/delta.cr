require "uuid"

module DeltaDB
  # The core identity types of the delta/history engine.
  #
  # These are UUID-backed newtypes recovered from `deltadb::delta` (and
  # `deltadb::history`) symbols. Zed/Delat represents each as a distinct type so
  # they cannot be accidentally mixed; we preserve that with distinct Crystal
  # structs over a shared `UUID` payload.

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

  # Identifies a timeline (a linear history of deltas).
  uuid_id TimelineId

  # Identifies a history (a set of timelines).
  uuid_id HistoryId

  # Identifies a single delta.
  uuid_id DeltaId

  # A monotonically-increasing version number within a timeline/history.
  #
  # Recovered from `deltadb::history::HistoryVersion`.
  struct HistoryVersion
    include Comparable(HistoryVersion)

    getter value : UInt64

    def initialize(@value : UInt64)
    end

    def self.zero : HistoryVersion
      HistoryVersion.new(0u64)
    end

    def <=>(other : HistoryVersion) : Int32
      @value <=> other.value
    end

    def to_s(io : IO) : Nil
      io << @value
    end
  end
end
