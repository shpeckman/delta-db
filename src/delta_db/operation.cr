# src/delta_db/operation.cr
module DeltaDB
  # A byte offset spanning the full (visible + deleted) text.
  alias FullOffset = UInt32

  # A single edit operation: replace `ranges` with `new_text` (1:1).
  #
  # Port of `crates/text/src/text.rs` `EditOperation`.
  struct EditOperation
    getter timestamp : Lamport
    getter version : Global
    getter ranges : Array(Range(FullOffset, FullOffset))
    getter new_text : Array(String)

    def initialize(@timestamp : Lamport, @version : Global, @ranges : Array(Range(FullOffset, FullOffset)), @new_text : Array(String))
    end
  end

  # An undo operation, mapping edited timestamps to undo counts.
  #
  # Port of `crates/text/src/text.rs` `UndoOperation`.
  struct UndoOperation
    getter timestamp : Lamport
    getter version : Global
    getter counts : Hash(Lamport, UInt32)

    def initialize(@timestamp : Lamport, @version : Global, @counts : Hash(Lamport, UInt32))
    end
  end

  # A buffer operation: an edit or an undo.
  alias Operation = EditOperation | UndoOperation
end
