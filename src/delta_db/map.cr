# src/delta_db/map.cr
module DeltaDB
  class Map
    getter entries : Hash(String, Entry)
    getter seal_state : SealState

    def initialize(@entries : Hash(String, Entry) = {} of String => Entry)
      @seal_state = SealState.new
    end

    def set(key : String, value : String, version : VersionVector = VersionVector.new) : Entry
      @seal_state.ensure_mutable!
      entry = Entry.register(value, version)
      @entries[key] = entry
      entry
    end

    def set_blob(key : String, value : Blob::Ref, version : VersionVector = VersionVector.new) : Entry
      @seal_state.ensure_mutable!
      entry = Entry.blob(value, version)
      @entries[key] = entry
      entry
    end

    def set_buffer(key : String, value : Buffer, version : VersionVector = VersionVector.new) : Entry
      @seal_state.ensure_mutable!
      entry = Entry.buffer(value, version)
      @entries[key] = entry
      entry
    end

    def set_map(key : String, value : Map, version : VersionVector = VersionVector.new) : Entry
      @seal_state.ensure_mutable!
      entry = Entry.map(value, version)
      @entries[key] = entry
      entry
    end

    def set_worktree(key : String, value : Worktree, version : VersionVector = VersionVector.new) : Entry
      @seal_state.ensure_mutable!
      entry = Entry.worktree(value, version)
      @entries[key] = entry
      entry
    end

    def apply(delta : Delta) : Nil
      operation = delta.operation || raise ArgumentError.new("delta has no client operation")
      case operation.kind
      in .set_register?
        set(operation.key, operation.text)
      in .set_blob?
        set_blob(operation.key, operation.blob.not_nil!)
      in .set_buffer?
        set_buffer(operation.key, operation.buffer.not_nil!)
      in .set_map?
        set_map(operation.key, operation.nested_map.not_nil!)
      in .set_worktree?
        set_worktree(operation.key, operation.worktree.not_nil!)
      in .edit_buffer?
        buffer = entry(operation.key).try(&.buffer) || raise NotFoundError.new("missing buffer: #{operation.key}")
        buffer.edit_as_actor(operation.ranges.zip(operation.new_text).to_a)
      in .edit_worktree?
        worktree = entry(operation.key).try(&.worktree) || raise NotFoundError.new("missing worktree: #{operation.key}")
        worktree.apply(operation.file_delta.not_nil!)
      in .delete?
        delete(operation.key)
      in .seal?
        seal(History::Version.from_id(DeltaBatchId.new(delta.timeline.uuid, delta.timestamp.value.to_u64)))
      end
    end

    def get(key : String) : String?
      @entries[key]?.try(&.register_value)
    end

    def entry(key : String) : Entry?
      @entries[key]?
    end

    def delete(key : String) : Entry?
      @seal_state.ensure_mutable!
      @entries.delete(key)
    end

    def changes(since : VersionVector) : Hash(String, Entry)
      @entries.select { |_, entry| entry.version.changed_since?(since) }
    end

    def restore(entries : Hash(String, Entry)) : Nil
      @seal_state.ensure_mutable!
      @entries = entries.dup
    end

    def seal(version : History::Version) : Nil
      @seal_state.seal(version)
    end

    def sealed? : Bool
      @seal_state.sealed?
    end
  end
end
