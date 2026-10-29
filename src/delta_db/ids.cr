# src/delta_db/ids.cr
require "uuid"

module DeltaDB
  # The core identity types of the delta/history engine.
  #
  # Recovered from `deltadb::delta` / `deltadb::history` symbols and validated
  # against the real database: UUID-backed newtypes, plus the composite
  # `TimelineId` (uuid + generation) and `DeltaBatchId` (uuid + ordinal), and
  # `HistoryVersion` (a sorted, deduplicated set of batch IDs).
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
end
