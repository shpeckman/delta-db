# src/delta_db/undo_history.cr
module DeltaDB
  class UndoHistory
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

    @undo_stack = Array(Entry).new
    @redo_stack = Array(Entry).new
    @transaction_depth = 0

    def initialize(@base_text : Rope)
      @operations = Hash(Lamport, Operation).new
    end

    def push(op : Operation) : Nil
      @operations[op.timestamp] = op
    end

    def start_transaction(clock : Clock) : Lamport?
      @transaction_depth += 1
      if @transaction_depth == 1
        id = clock.tick
        @undo_stack << Entry.new(Transaction.new(id))
        id
      end
    end

    def end_transaction : Entry?
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

    def push_undo(op_id : Lamport) : Nil
      if @operations[op_id]?.is_a?(EditOperation)
        entry = @undo_stack.last?
        entry.transaction.edit_ids << op_id if entry
      end
    end

    def undo : Entry?
      entry = @undo_stack.pop?
      @redo_stack << entry if entry
      entry
    end

    def redo : Entry?
      entry = @redo_stack.pop?
      @undo_stack << entry if entry
      entry
    end

    def peek_undo_stack : Entry?
      @undo_stack.last?
    end

    def peek_redo_stack : Entry?
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
