# src/delta_db/transaction.cr
module DeltaDB
  # A transaction grouping a set of edits for undo/redo.
  #
  # Port of `crates/text/src/text.rs` `Transaction`.
  struct Transaction
    getter id : Lamport
    getter edit_ids : Array(Lamport)
    getter start : Global

    def initialize(@id : Lamport, @edit_ids : Array(Lamport) = [] of Lamport, @start : Global = Global.new)
    end
  end
end
