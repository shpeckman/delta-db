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
