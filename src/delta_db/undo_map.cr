# src/delta_db/undo_map.cr
module DeltaDB
  class UndoMap
    @entries = Hash(Lamport, Array({Lamport, UInt32})).new

    def insert(undo : UndoOperation) : Nil
      undo.counts.each do |edit_id, count|
        entries = @entries[edit_id] ||= [] of {Lamport, UInt32}
        entries << {undo.timestamp, count} unless entries.any? { |entry| entry[0] == undo.timestamp }
      end
    end

    def undo_count(edit_id : Lamport) : UInt32
      @entries[edit_id]?.try(&.max_of?(&.[1])) || 0u32
    end

    def undone?(edit_id : Lamport) : Bool
      undo_count(edit_id).odd?
    end

    def was_undone(edit_id : Lamport, version : Global) : Bool
      count = 0u32
      @entries[edit_id]?.try do |entries|
        entries.each do |undo_id, undo_count|
          count = Math.max(count, undo_count) if version.observed?(undo_id)
        end
      end
      count.odd?
    end
  end
end
