# src/delta_db/operation.cr
module DeltaDB
  alias FullOffset = UInt32

  struct EditOperation
    getter timestamp : Lamport
    getter version : Global
    getter ranges : Array(Range(FullOffset, FullOffset))
    getter new_text : Array(String)

    def initialize(@timestamp : Lamport, @version : Global, @ranges : Array(Range(FullOffset, FullOffset)), @new_text : Array(String))
    end
  end

  struct UndoOperation
    getter timestamp : Lamport
    getter version : Global
    getter counts : Hash(Lamport, UInt32)

    def initialize(@timestamp : Lamport, @version : Global, @counts : Hash(Lamport, UInt32))
    end
  end

  alias Operation = EditOperation | UndoOperation
end
