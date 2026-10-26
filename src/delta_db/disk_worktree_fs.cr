module DeltaDB
  # Filesystem helpers backing the disk worktree.
  #
  # Clean-room port of `deltadb::disk_worktree_fs` (recovered function names:
  # `temp_file_path`, `path_contains_temp_component`, `probe_case_sensitivity`,
  # `scan_directory`, `remove_dir_all_clearing_permissions`,
  # `grant_owner_directory_access`).
  module DiskWorktreeFs
    TEMP_PREFIX = ".delta-fs-"

    @@temp_counter = 0u64

    # A unique temp-file path inside `dir`.
    def self.temp_file_path(dir : String) : String
      @@temp_counter += 1
      File.join(dir, "#{TEMP_PREFIX}#{Process.pid}-#{@@temp_counter}")
    end

    # Whether any component of `path` is a Delta temp component.
    def self.path_contains_temp_component(path : String) : Bool
      path.split(File::SEPARATOR).any? { |comp| comp.starts_with?(TEMP_PREFIX) }
    end

    # List a directory's immediate entries as `{name, kind}`.
    def self.scan_directory(dir : String) : Array({String, FileTreeEntryKind})
      Dir.children(dir).map do |name|
        full = File.join(dir, name)
        kind = if File.symlink?(full)
                 FileTreeEntryKind::Symlink
               elsif File.directory?(full)
                 FileTreeEntryKind::Directory
               else
                 FileTreeEntryKind::File
               end
        {name, kind}
      end
    end

    # Whether the filesystem at `dir` is case-sensitive.
    def self.probe_case_sensitivity(dir : String) : Bool
      base = "deltaCaseProbe_#{Process.pid}_#{Random.rand(1_000_000)}"
      upper = File.join(dir, base.upcase)
      File.write(upper, "")
      begin
        # On a case-insensitive FS, the differently-cased name resolves to the
        # same file.
        !File.exists?(File.join(dir, base.downcase))
      ensure
        File.delete(upper) if File.exists?(upper)
      end
    end

    # Recursively remove a directory, clearing permissions on contents first
    # (so read-only files don't block deletion).
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

    # Grant the owner read/write/execute access on a directory.
    def self.grant_owner_directory_access(path : String) : Nil
      File.chmod(path, 0o700)
    rescue File::Error
    end
  end
end
