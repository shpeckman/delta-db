module DeltaDB
  # Identifier for an inode in the file tree (a filesystem inode number).
  #
  # Recovered from `deltadb::file_tree_state::InodeId`.
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

  # The kind of a file-tree entry.
  #
  # Recovered from `deltadb::file_tree_state::FileTreeEntryKind`.
  enum FileTreeEntryKind
    File
    Directory
    Symlink
  end

  # A location (path) at which an inode is reachable.
  #
  # Clean-room reconstruction of `deltadb::file_tree_state::InodeLocation`.
  struct InodeLocation
    getter path : String

    def initialize(@path : String)
    end
  end

  # Payload for a regular-file inode: a reference to its content blob.
  #
  # Clean-room reconstruction of `deltadb::file_tree_state::FilePayload`.
  struct FilePayload
    getter content_id : DeltaId

    def initialize(@content_id : DeltaId)
    end
  end

  # Payload for a symlink inode: its target path.
  #
  # Clean-room reconstruction of `deltadb::file_tree_state::SymlinkPayload`.
  struct SymlinkPayload
    getter target : String

    def initialize(@target : String)
    end
  end

  # An inode: id, kind, and a kind-specific payload.
  #
  # Clean-room reconstruction of `deltadb::file_tree_state::Inode`.
  struct Inode
    getter id : InodeId
    getter kind : FileTreeEntryKind
    getter payload : FilePayload | SymlinkPayload | Nil

    def initialize(@id : InodeId, @kind : FileTreeEntryKind, @payload : FilePayload | SymlinkPayload | Nil = nil)
    end
  end

  # A parent -> child edge in the file tree.
  #
  # Clean-room reconstruction of `deltadb::file_tree_state::ChildEdge`.
  struct ChildEdge
    getter parent : InodeId
    getter child : InodeId
    getter name : String

    def initialize(@parent : InodeId, @child : InodeId, @name : String)
    end
  end

  # Key for a child edge (parent id + child name).
  #
  # Clean-room reconstruction of `deltadb::file_tree_state::ChildEdgeKey`.
  struct ChildEdgeKey
    getter parent : InodeId
    getter name : String

    def initialize(@parent : InodeId, @name : String)
    end
  end

  # An edge that would form a symlink cycle.
  #
  # Clean-room reconstruction of `deltadb::file_tree_state::CycleEdge`.
  struct CycleEdge
    getter from : InodeId
    getter to : InodeId

    def initialize(@from : InodeId, @to : InodeId)
    end
  end
end
