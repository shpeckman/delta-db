# src/delta_db/worktree/entry.cr
module DeltaDB
  class Worktree
    class Entry
      property path : String
      property kind : FileMode
      property text : String?
      property blob : BlobRef?
      property symlink_target : String?
      property line_ending : Text::LineEnding

      def initialize(
        @path : String,
        @kind : FileMode = FileMode::File,
        @text : String? = nil,
        @blob : BlobRef? = nil,
        @symlink_target : String? = nil,
        @line_ending : Text::LineEnding = Text::LineEnding::Lf,
      )
      end

      def copy : Entry
        Entry.new(@path, @kind, @text, @blob, @symlink_target, @line_ending)
      end
    end
  end
end
