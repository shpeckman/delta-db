# src/delta_db/delta_application.cr
module DeltaDB
  module DeltaApplication
    def self.apply(target : Map, delta : Delta) : Nil
      operation = delta.operation || raise ArgumentError.new("delta has no client operation")
      case operation.kind
      when ClientOperationKind::SetRegister
        target.set(operation.key, operation.text)
      when ClientOperationKind::SetBlob
        target.set_blob(operation.key, operation.blob.not_nil!)
      when ClientOperationKind::SetBuffer
        target.set_buffer(operation.key, operation.buffer.not_nil!)
      when ClientOperationKind::SetMap
        target.set_map(operation.key, operation.nested_map.not_nil!)
      when ClientOperationKind::SetWorktree
        target.set_worktree(operation.key, operation.worktree.not_nil!)
      when ClientOperationKind::EditBuffer
        buffer = target.entry(operation.key).try(&.buffer) || raise ArgumentError.new("missing buffer: #{operation.key}")
        buffer.edit_as_actor(operation.ranges.zip(operation.new_text).to_a)
      when ClientOperationKind::EditWorktree
        worktree = target.entry(operation.key).try(&.worktree) || raise ArgumentError.new("missing worktree: #{operation.key}")
        worktree.apply(operation.file_delta.not_nil!)
      when ClientOperationKind::Delete
        target.delete(operation.key)
      when ClientOperationKind::Seal
        target.seal(HistoryVersion.from_id(DeltaBatchId.new(delta.timeline.uuid, delta.timestamp.value.to_u64)))
      end
    end

    def self.apply(target : ClientBuffer, delta : Delta) : Nil
      operation = delta.operation || raise ArgumentError.new("delta has no client operation")
      case operation.kind
      when ClientOperationKind::EditBuffer
        target.edit_as_actor(operation.ranges.zip(operation.new_text).to_a)
      when ClientOperationKind::Seal
        target.seal
      else
        raise ArgumentError.new("unsupported buffer operation: #{operation.kind}")
      end
    end

    def self.apply(target : Worktree, delta : Delta) : Nil
      operation = delta.operation || raise ArgumentError.new("delta has no client operation")
      case operation.kind
      when ClientOperationKind::EditWorktree
        target.apply(operation.file_delta.not_nil!)
      when ClientOperationKind::Seal
        target.seal
      else
        raise ArgumentError.new("unsupported worktree operation: #{operation.kind}")
      end
    end
  end
end
