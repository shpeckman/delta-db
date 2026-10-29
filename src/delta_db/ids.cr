# src/delta_db/ids.cr
require "uuid"

module DeltaDB
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

  uuid_id ActorUuid

  uuid_id LocalRepositoryId

  uuid_id RemoteRepositoryId

  uuid_id HistoryId

  uuid_id DeltaId
end
