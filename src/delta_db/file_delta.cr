# src/delta_db/file_delta.cr
module DeltaDB
  abstract struct FileDelta
    struct CreateFile < FileDelta
      getter path : String
      getter mode : FileMode
      getter line_endings : Text::LineEnding?

      def initialize(@path : String, @mode : FileMode = FileMode::File, @line_endings : Text::LineEnding? = nil)
      end
    end

    struct Edit < FileDelta
      getter path : String
      getter new_text : String

      def initialize(@path : String, @new_text : String)
      end
    end

    struct Delete < FileDelta
      getter path : String

      def initialize(@path : String)
      end
    end

    struct Rename < FileDelta
      getter old_path : String
      getter new_path : String

      def initialize(@old_path : String, @new_path : String)
      end
    end

    struct SetMode < FileDelta
      getter path : String
      getter mode : FileMode

      def initialize(@path : String, @mode : FileMode)
      end
    end

    struct SetLineEndings < FileDelta
      getter path : String
      getter line_endings : Text::LineEnding

      def initialize(@path : String, @line_endings : Text::LineEnding)
      end
    end

    struct CreateDir < FileDelta
      getter path : String

      def initialize(@path : String)
      end
    end

    struct CreateSymlink < FileDelta
      getter path : String
      getter target : String

      def initialize(@path : String, @target : String)
      end
    end
  end
end
