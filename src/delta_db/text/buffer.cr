# src/delta_db/text/buffer.cr
module DeltaDB
  module Text
    class Buffer
      getter snapshot : Snapshot
      getter history : UndoHistory
      getter lamport_clock : Clock

      def initialize(replica_id : ReplicaId, remote_id : BufferId, base_text : String)
        line_ending = base_text.includes?("\r\n") ? LineEnding::Crlf : LineEnding::Lf
        @snapshot = Snapshot.build(LineEnding.normalize(base_text), remote_id, replica_id, line_ending)
        @history = UndoHistory.new(@snapshot.visible_text)
        @lamport_clock = Clock.new(Lamport.new(replica_id))
        @lamport_clock.observe(Lamport.new(ReplicaId::LOCAL)) unless base_text.empty?
      end

      def text : String
        @snapshot.text
      end

      def bytesize : Int32
        @snapshot.bytesize
      end

      def version : VersionVector
        @snapshot.version.clone
      end

      def remote_id : BufferId
        @snapshot.remote_id
      end

      def replica_id : ReplicaId
        @snapshot.replica_id
      end

      def edit(edits : Array({Range(Int32, Int32), String})) : EditOperation
        @history.start_transaction(@lamport_clock)
        timestamp = @lamport_clock.tick
        operation = @snapshot.apply_local_edit(edits.map(&.[0]), edits.map(&.[1]), timestamp)
        @history.push(operation)
        @history.push_undo(timestamp)
        @snapshot.version.observe(timestamp)
        @history.end_transaction
        operation
      end

      def apply_ops(ops : Array(Operation)) : Array(Operation)
        ops.each { |op| @history.push(op) }
        applied = @snapshot.apply_ops(ops)
        applied.each { |op| @lamport_clock.observe(op.timestamp) }
        applied
      end

      def apply(op : Operation) : Array(Operation)
        apply_ops([op])
      end

      def start_transaction : Lamport?
        @history.start_transaction(@lamport_clock)
      end

      def end_transaction : UndoHistory::Entry?
        @history.end_transaction
      end

      def undo : UndoOperation?
        entry = @history.undo
        entry ? undo_or_redo(entry.transaction) : nil
      end

      def redo : UndoOperation?
        entry = @history.redo
        entry ? undo_or_redo(entry.transaction) : nil
      end

      def undo_or_redo(transaction : UndoHistory::Transaction) : UndoOperation
        counts = Hash(Lamport, UInt32).new
        transaction.edit_ids.each do |edit_id|
          counts[edit_id] = @snapshot.undo_map.undo_count(edit_id) + 1u32
        end
        undo_operations(counts)
      end

      def undo_operations(counts : Hash(Lamport, UInt32)) : UndoOperation
        timestamp = @lamport_clock.tick
        operation = UndoOperation.new(timestamp, @snapshot.version.clone, counts)
        @snapshot.apply(operation)
        @snapshot.version.observe(timestamp)
        @history.push(operation)
        operation
      end

      def anchor_before(offset : Int32) : Anchor
        @snapshot.anchor_before(offset)
      end

      def anchor_after(offset : Int32) : Anchor
        @snapshot.anchor_after(offset)
      end

      def deferred_ops_count : Int32
        @snapshot.deferred_ops_count
      end

      def check_invariants : Nil
        @snapshot.check_invariants
      end
    end
  end
end
