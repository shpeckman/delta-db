# src/delta_db/worktree/disk/read_diagnostics.cr
module DeltaDB
  class Worktree
    module Disk
      struct ReadDiagnostics
        DEFAULT_SLOW_THRESHOLD = 100.milliseconds

        getter path : String
        getter bytes : UInt64
        getter duration : Time::Span

        def initialize(@path : String, @bytes : UInt64, @duration : Time::Span)
        end

        def self.load_file_blob(path : String) : {Bytes, FileReadDiagnostics}?
          return nil unless File.exists?(path)
          started = Time.instant
          bytes = File.read(path).to_slice
          duration = Time.instant - started
          {bytes, DeltaDB::FileReadDiagnostics.new(path, bytes.size.to_u64, duration)}
        end

        def self.warn_if_read_slow(diag : FileReadDiagnostics, threshold : Time::Span = DEFAULT_SLOW_THRESHOLD) : Nil
          if diag.duration > threshold
            STDERR.puts "slow file read: #{diag.path} (#{diag.bytes} bytes in #{diag.duration.total_milliseconds.round(1)}ms)"
          end
        end
      end
    end
  end
end
