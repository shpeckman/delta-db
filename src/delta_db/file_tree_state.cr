# src/delta_db/file_tree_state.cr
module DeltaDB
  struct InodeId
    include Comparable(InodeId)

    getter value : UInt64

    def initialize(@value : UInt64)
    end

    def <=>(other : InodeId) : Int32
      @value <=> other.value
    end

    def to_s(io : IO) : Nil
      io << @value
    end
  end

  enum FileTreeEntryKind
    File
    Directory
    Symlink
  end

  struct InodeLocation
    getter path : String

    def initialize(@path : String)
    end
  end

  struct FilePayload
    getter content_id : DeltaId

    def initialize(@content_id : DeltaId)
    end
  end

  struct SymlinkPayload
    getter target : String

    def initialize(@target : String)
    end
  end

  struct Inode
    getter id : InodeId
    getter kind : FileTreeEntryKind
    getter payload : FilePayload | SymlinkPayload | Nil

    def initialize(@id : InodeId, @kind : FileTreeEntryKind, @payload : FilePayload | SymlinkPayload | Nil = nil)
    end
  end

  struct ChildEdge
    getter parent : InodeId
    getter child : InodeId
    getter name : String

    def initialize(@parent : InodeId, @child : InodeId, @name : String)
    end
  end

  struct ChildEdgeKey
    getter parent : InodeId
    getter name : String

    def initialize(@parent : InodeId, @name : String)
    end
  end

  struct CycleEdge
    getter from : InodeId
    getter to : InodeId

    def initialize(@from : InodeId, @to : InodeId)
    end
  end
end
