# src/delta_db/text/operation.cr
module DeltaDB
  module Text
    alias FullOffset = UInt32

    struct EditOperation
      getter timestamp : Lamport
      getter version : VersionVector
      getter ranges : Array(Range(FullOffset, FullOffset))
      getter new_text : Array(String)

      def initialize(@timestamp : Lamport, @version : VersionVector, @ranges : Array(Range(FullOffset, FullOffset)), @new_text : Array(String))
      end
    end

    struct UndoOperation
      getter timestamp : Lamport
      getter version : VersionVector
      getter counts : Hash(Lamport, UInt32)

      def initialize(@timestamp : Lamport, @version : VersionVector, @counts : Hash(Lamport, UInt32))
      end
    end

    alias Operation = EditOperation | UndoOperation
  end
end
