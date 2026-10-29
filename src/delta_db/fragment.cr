# src/delta_db/fragment.cr
module DeltaDB
  struct Fragment
    getter id : Locator
    getter timestamp : Lamport
    getter insertion_offset : UInt32
    getter len : UInt32
    property visible : Bool
    property deletions : Array(Lamport)
    property max_undos : Global
    getter text : String

    def initialize(
      @id : Locator,
      @timestamp : Lamport,
      @insertion_offset : UInt32 = 0u32,
      @len : UInt32 = 0u32,
      @visible : Bool = true,
      @deletions : Array(Lamport) = [] of Lamport,
      @max_undos : Global = Global.new,
      @text : String = "",
    )
    end

    def is_visible(undos : UndoMap) : Bool
      !undos.undone?(@timestamp) && @deletions.all? { |deletion| undos.undone?(deletion) }
    end

    def was_visible(version : Global, undos : UndoMap) : Bool
      version.observed?(@timestamp) && !undos.was_undone(@timestamp, version) &&
        @deletions.all? { |deletion| !version.observed?(deletion) || undos.was_undone(deletion, version) }
    end
  end
end
