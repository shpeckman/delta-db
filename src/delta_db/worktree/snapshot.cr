# src/delta_db/worktree/snapshot.cr
module DeltaDB
  class Worktree
    class Snapshot
      getter version : History::Version
      getter files : Array(Entry)

      def initialize(@version : History::Version, @files : Array(Entry))
      end

      def file(path : String) : Entry?
        @files.find { |file| file.path == path }
      end
    end
  end
end
