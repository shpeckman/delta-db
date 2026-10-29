# src/delta_db/worktree_snapshot.cr
module DeltaDB
  class WorktreeSnapshot
    getter version : HistoryVersion
    getter files : Array(WorktreeFile)

    def initialize(@version : HistoryVersion, @files : Array(WorktreeFile))
    end

    def file(path : String) : WorktreeFile?
      @files.find { |file| file.path == path }
    end
  end
end
