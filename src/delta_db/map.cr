# src/delta_db/map.cr
module DeltaDB
  class Map
    getter entries : Hash(String, MapEntry)
    getter seal_state : SealState

    def initialize(@entries : Hash(String, MapEntry) = {} of String => MapEntry)
      @seal_state = SealState.new
    end

    def set(key : String, value : String, version : Global = Global.new) : MapEntry
      @seal_state.ensure_mutable!
      entry = MapEntry.register(value, version)
      @entries[key] = entry
      entry
    end

    def set_blob(key : String, value : BlobRef, version : Global = Global.new) : MapEntry
      @seal_state.ensure_mutable!
      entry = MapEntry.blob(value, version)
      @entries[key] = entry
      entry
    end

    def set_buffer(key : String, value : Buffer, version : Global = Global.new) : MapEntry
      @seal_state.ensure_mutable!
      entry = MapEntry.buffer(value, version)
      @entries[key] = entry
      entry
    end

    def set_map(key : String, value : Map, version : Global = Global.new) : MapEntry
      @seal_state.ensure_mutable!
      entry = MapEntry.map(value, version)
      @entries[key] = entry
      entry
    end

    def set_worktree(key : String, value : Worktree, version : Global = Global.new) : MapEntry
      @seal_state.ensure_mutable!
      entry = MapEntry.worktree(value, version)
      @entries[key] = entry
      entry
    end

    def get(key : String) : String?
      @entries[key]?.try(&.register_value)
    end

    def entry(key : String) : MapEntry?
      @entries[key]?
    end

    def delete(key : String) : MapEntry?
      @seal_state.ensure_mutable!
      @entries.delete(key)
    end

    def changes(since : Global) : Hash(String, MapEntry)
      @entries.select { |_, entry| entry.version.changed_since?(since) }
    end

    def restore(entries : Hash(String, MapEntry)) : Nil
      @seal_state.ensure_mutable!
      @entries = entries.dup
    end

    def seal(version : HistoryVersion) : Nil
      @seal_state.seal(version)
    end

    def sealed? : Bool
      @seal_state.sealed?
    end
  end
end
