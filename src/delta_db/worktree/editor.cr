# src/delta_db/worktree/editor.cr
module DeltaDB
  class Worktree
    class Editor
      getter worktree : Worktree

      def initialize(@worktree : Worktree)
        @buffers = {} of String => ClientBuffer
        @next_buffer_id = 1u64
      end

      def open(path : String, replica_id : ReplicaId = ReplicaId::LOCAL) : ClientBuffer
        @buffers[path] ||= begin
          text = @worktree.read(path) || raise NotFoundError.new("missing text file: #{path}")
          id = BufferId.new(@next_buffer_id)
          @next_buffer_id += 1u64
          ClientBuffer.new(id, replica_id, text)
        end
      end

      def read(path : String) : String
        if buffer = @buffers[path]?
          buffer.text
        else
          @worktree.read(path) || raise NotFoundError.new("missing text file: #{path}")
        end
      end

      def edit(path : String, ranges : Array(Range(Int32, Int32)), new_text : Array(String), replica_id : ReplicaId = ReplicaId::LOCAL) : EditOperation
        open(path, replica_id).edit_as_actor(ranges.zip(new_text).to_a)
      end

      def save(path : String) : Nil
        buffer = @buffers.fetch(path) { raise NotFoundError.new("buffer is not open: #{path}") }
        @worktree.apply(EditFileDelta.new(path, buffer.text))
      end

      def fragment_index(path : String) : FragmentIndex
        FragmentIndex.from_fragments(open(path).fragments)
      end

      def snapshot : WorktreeSnapshot
        @worktree.snapshot
      end
    end
  end
end
