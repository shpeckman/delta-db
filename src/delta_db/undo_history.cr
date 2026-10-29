# src/delta_db/undo_history.cr
module DeltaDB
  # The undo/redo history of a buffer.
  #
  # Clean-room port of `crates/text/src/text.rs` `History`. The time-based
  # transaction grouping (`group_interval`, `Instant`) is dropped; the core
  # undo/redo stack + operations map semantics are preserved.
  class UndoHistory
    # An entry on the undo/redo stack.
    #
    # Port of `crates/text/src/text.rs` `HistoryEntry`.
    struct Entry
      getter transaction : Transaction
      property suppress_grouping : Bool

      def initialize(@transaction : Transaction, @suppress_grouping : Bool = false)
      end

      def transaction_id : Lamport
        @transaction.id
      end
    end

    getter base_text : Rope
    getter operations : Hash(Lamport, Operation)

    @undo_stack = Array(HistoryEntry).new
    @redo_stack = Array(HistoryEntry).new
    @transaction_depth = 0

    def initialize(@base_text : Rope)
      @operations = Hash(Lamport, Operation).new
    end

    # Record an operation.
    def push(op : Operation) : Nil
      @operations[op.timestamp] = op
    end

    # Begin a transaction; returns its id when it is the outermost transaction.
    def start_transaction(clock : Clock) : Lamport?
      @transaction_depth += 1
      if @transaction_depth == 1
        id = clock.tick
        @undo_stack << HistoryEntry.new(Transaction.new(id))
        id
      end
    end

    # End the current transaction; finalizes and returns the entry at depth 0.
    def end_transaction : HistoryEntry?
      @transaction_depth -= 1
      if @transaction_depth == 0
        entry = @undo_stack.last?
        if entry.nil? || entry.transaction.edit_ids.empty?
          @undo_stack.pop
          nil
        else
          @redo_stack.clear
          entry
        end
      end
    end

    # Record that `op_id` is part of the current transaction (if it is an edit).
    def push_undo(op_id : Lamport) : Nil
      if @operations[op_id]?.is_a?(EditOperation)
        entry = @undo_stack.last?
        entry.transaction.edit_ids << op_id if entry
      end
    end

    # Undo: move the top undo entry onto the redo stack.
    def undo : HistoryEntry?
      entry = @undo_stack.pop?
      @redo_stack << entry if entry
      entry
    end

    # Redo: move the top redo entry back onto the undo stack.
    def redo : HistoryEntry?
      entry = @redo_stack.pop?
      @undo_stack << entry if entry
      entry
    end

    def peek_undo_stack : HistoryEntry?
      @undo_stack.last?
    end

    def peek_redo_stack : HistoryEntry?
      @redo_stack.last?
    end

    def undo_depth : Int32
      @undo_stack.size
    end

    def redo_depth : Int32
      @redo_stack.size
    end
  end
end
