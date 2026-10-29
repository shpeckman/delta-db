# src/delta_db/worktree/disk.cr
module DeltaDB
  class Worktree
    module Disk
      TEMP_PREFIX = ".delta-fs-"

      @@temp_counter = 0u64

      def self.temp_file_path(dir : String) : String
        @@temp_counter += 1
        File.join(dir, "#{TEMP_PREFIX}#{Process.pid}-#{@@temp_counter}")
      end

      def self.path_contains_temp_component(path : String) : Bool
        path.split(File::SEPARATOR).any? { |comp| comp.starts_with?(TEMP_PREFIX) }
      end

      def self.scan_directory(dir : String) : Array({String, FileMode})
        Dir.children(dir).map do |name|
          full = File.join(dir, name)
          kind = if File.symlink?(full)
                   FileMode::Symlink
                 elsif File.directory?(full)
                   FileMode::Directory
                 else
                   FileMode::File
                 end
          {name, kind}
        end
      end

      def self.probe_case_sensitivity(dir : String) : Bool
        base = "deltaCaseProbe_#{Process.pid}_#{Random.rand(1_000_000)}"
        upper = File.join(dir, base.upcase)
        File.write(upper, "")
        begin
          !File.exists?(File.join(dir, base.downcase))
        ensure
          File.delete(upper) if File.exists?(upper)
        end
      end

      def self.remove_dir_all_clearing_permissions(dir : String) : Nil
        return unless Dir.exists?(dir)
        Dir.children(dir).each do |child|
          full = File.join(dir, child)
          if File.directory?(full) && !File.symlink?(full)
            remove_dir_all_clearing_permissions(full)
          else
            begin
              File.chmod(full, 0o600)
            rescue File::Error
            end
            File.delete(full)
          end
        end
        begin
          File.chmod(dir, 0o700)
        rescue File::Error
        end
        Dir.delete(dir)
      end

      def self.grant_owner_directory_access(path : String) : Nil
        File.chmod(path, 0o700)
      rescue File::Error
      end
    end
  end
end
