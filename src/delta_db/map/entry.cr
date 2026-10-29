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

      getter kind : Kind
      getter register_value : String?
      getter blob : Blob::Ref?
      getter buffer : Buffer?
      getter nested_map : Map?
      getter worktree : Worktree?
      getter version : VersionVector

      def initialize(
        @kind : Kind,
        @version : VersionVector,
        @register_value : String? = nil,
        @blob : Blob::Ref? = nil,
        @buffer : Buffer? = nil,
        @nested_map : Map? = nil,
        @worktree : Worktree? = nil,
      )
      end

      def self.register(value : String, version : VersionVector) : Entry
        new(Kind::Register, version, register_value: value)
      end

      def self.blob(value : Blob::Ref, version : VersionVector) : Entry
        new(Kind::Blob, version, blob: value)
      end

      def self.buffer(value : Buffer, version : VersionVector) : Entry
        new(Kind::Buffer, version, buffer: value)
      end

      def self.map(value : Map, version : VersionVector) : Entry
        new(Kind::Map, version, nested_map: value)
      end

      def self.worktree(value : Worktree, version : VersionVector) : Entry
        new(Kind::Worktree, version, worktree: value)
      end
    end
  end
end
