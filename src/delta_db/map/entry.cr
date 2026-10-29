# src/delta_db/map/entry.cr
module DeltaDB
  class Map
    class Entry
      enum Kind
        Register
        Blob
        Buffer
        Map
        Worktree
      end

      getter kind : MapEntryKind
      getter register_value : String?
      getter blob : BlobRef?
      getter buffer : Buffer?
      getter nested_map : Map?
      getter worktree : Worktree?
      getter version : Global

      def initialize(
        @kind : MapEntryKind,
        @version : Global,
        @register_value : String? = nil,
        @blob : BlobRef? = nil,
        @buffer : Buffer? = nil,
        @nested_map : Map? = nil,
        @worktree : Worktree? = nil,
      )
      end

      def self.register(value : String, version : Global) : MapEntry
        new(MapEntryKind::Register, version, register_value: value)
      end

      def self.blob(value : BlobRef, version : Global) : MapEntry
        new(MapEntryKind::Blob, version, blob: value)
      end

      def self.buffer(value : Buffer, version : Global) : MapEntry
        new(MapEntryKind::Buffer, version, buffer: value)
      end

      def self.map(value : Map, version : Global) : MapEntry
        new(MapEntryKind::Map, version, nested_map: value)
      end

      def self.worktree(value : Worktree, version : Global) : MapEntry
        new(MapEntryKind::Worktree, version, worktree: value)
      end
    end
  end
end
