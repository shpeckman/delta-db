# src/delta_db/worktree/snapshot.cr
module DeltaDB
  class Worktree
    class Snapshot
      getter version : HistoryVersion
      getter files : Array(WorktreeFile)

      def initialize(@version : HistoryVersion, @files : Array(WorktreeFile))
      end

      def file(path : String) : WorktreeFile?
        @files.find { |file| file.path == path }
      end
    end
  end
end
