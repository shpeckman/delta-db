module DeltaDB
  # A register holding an arbitrary (JSON-serializable) value — the base CRDT
  # register used as a `Map` entry.
  #
  # Clean-room reconstruction of `deltadb::client::AnyRegister`.
  struct AnyRegister(T)
    getter value : T

    def initialize(@value : T)
    end
  end

  # A buffer entry in the CRDT map: a text buffer identified by id and its
  # ordered fragments.
  #
  # Clean-room reconstruction of `deltadb::client::Buffer` (fields `buffer_id`,
  # `fragments` recovered from the `versioned` deserializer).
  struct Buffer
    getter buffer_id : BufferId
    getter fragments : Array(Fragment)

    def initialize(@buffer_id : BufferId, @fragments : Array(Fragment) = [] of Fragment)
    end
  end

  # A CRDT map: a keyed collection of register values.
  #
  # Clean-room reconstruction of `deltadb::client::Map`. The full upstream map
  # has typed entries (register/blob/buffer/nested-map/worktree) resolved
  # through `map_changes`/`map_entries`; here we model the register-value core.
  class Map
    getter entries : Hash(String, AnyRegister(String))

    def initialize(@entries = Hash(String, AnyRegister(String)).new)
    end

    def set(key : String, value : String) : Nil
      @entries[key] = AnyRegister(String).new(value)
    end

    def get(key : String) : String?
      @entries[key]?.try(&.value)
    end
  end

  # A CRDT replica: an actor id, a Lamport clock, and a replicated value of
  # type `T` (a `Map`, `Buffer`, `Worktree`, etc.).
  #
  # Clean-room reconstruction of `deltadb::client::Replica<T>` (fields
  # `actor_id`, `clock`, `value`).
  class Replica(T)
    getter actor_id : ReplicaId
    getter clock : Clock
    getter value : T

    def initialize(@value : T, @actor_id : ReplicaId = ReplicaId::LOCAL, @clock : Clock = Clock.new)
    end

    def tick : Lamport
      @clock.tick
    end
  end
end
