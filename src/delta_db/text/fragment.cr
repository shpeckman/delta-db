# src/delta_db/text/fragment.cr
module DeltaDB
  module Text
    struct Fragment
      getter id : Locator
      getter timestamp : Lamport
      getter insertion_offset : UInt32
      getter bytesize : UInt32
      property visible : Bool
      property deletions : Array(Lamport)
      property max_undos : VersionVector
      getter text : String

      def initialize(
        @id : Locator,
        @timestamp : Lamport,
        @insertion_offset : UInt32 = 0u32,
        @bytesize : UInt32 = 0u32,
        @visible : Bool = true,
        @deletions : Array(Lamport) = [] of Lamport,
        @max_undos : VersionVector = VersionVector.new,
        @text : String = "",
      )
      end

      def is_visible(undos : UndoMap) : Bool
        !undos.undone?(@timestamp) && @deletions.all? { |deletion| undos.undone?(deletion) }
      end

      def was_visible(version : VersionVector, undos : UndoMap) : Bool
        version.observed?(@timestamp) && !undos.was_undone(@timestamp, version) &&
          @deletions.all? { |deletion| !version.observed?(deletion) || undos.was_undone(deletion, version) }
      end
    end
  end
end
