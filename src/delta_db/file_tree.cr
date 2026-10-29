# src/delta_db/file_tree.cr
module DeltaDB
  enum FileMode
    File
    Directory
    Symlink
  end

  enum FileContentKind
    Text
    Binary
  end

  struct CreateFileDelta
    getter path : String
    getter mode : FileMode
    getter line_endings : LineEnding?

    def initialize(@path : String, @mode : FileMode = FileMode::File, @line_endings : LineEnding? = nil)
    end
  end

  struct EditFileDelta
    getter path : String
    getter new_text : String

    def initialize(@path : String, @new_text : String)
    end
  end

  struct DeleteDelta
    getter path : String

    def initialize(@path : String)
    end
  end

  struct RenameDelta
    getter old_path : String
    getter new_path : String

    def initialize(@old_path : String, @new_path : String)
    end
  end

  struct SetModeDelta
    getter path : String
    getter mode : FileMode

    def initialize(@path : String, @mode : FileMode)
    end
  end

  struct SetLineEndingsDelta
    getter path : String
    getter line_endings : LineEnding

    def initialize(@path : String, @line_endings : LineEnding)
    end
  end

  struct CreateDirDelta
    getter path : String

    def initialize(@path : String)
    end
  end

  struct CreateSymlinkDelta
    getter path : String
    getter target : String

    def initialize(@path : String, @target : String)
    end
  end

  alias FileDelta = CreateFileDelta | EditFileDelta | DeleteDelta | RenameDelta | SetModeDelta | SetLineEndingsDelta | CreateDirDelta | CreateSymlinkDelta
end
