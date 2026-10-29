# src/delta_db/worktree.cr
module DeltaDB
  class Worktree
    getter files : Hash(String, Entry)
    getter blob_store : Blob::Store
    getter seal_state : SealState
    getter timeline : TimelineId

    def initialize(@timeline : TimelineId = TimelineId.random, @blob_store : Blob::Store = Blob::Store.new)
      @files = {} of String => Entry
      @seal_state = SealState.new
      @version = History::Version.new
      @next_ordinal = 1u64
    end

    def create(path : String, text : String = "", mode : FileMode = FileMode::File, line_ending : LineEnding? = nil) : Entry
      @seal_state.ensure_mutable!
      if @files.has_key?(path)
        raise ArgumentError.new("path already exists: #{path}")
      end
      if mode.symlink?
        raise ArgumentError.new("use FileDelta::CreateSymlink for symlinks")
      end

      file = Entry.new(path, mode, line_ending: line_ending || Text::LineEnding::Lf)
      if mode.file?
        file.text = Text::LineEnding.normalize(text)
        file.blob = @blob_store.put(file.text.not_nil!.to_slice)
      end
      @files[path] = file
      advance_version
      file
    end

    def apply(delta : FileDelta) : Nil
      @seal_state.ensure_mutable!
      case delta
      when FileDelta::CreateFile
        create(delta.path, "", delta.mode, delta.line_endings)
      when FileDelta::Edit
        write(delta.path, delta.new_text)
      when FileDelta::Delete
        @files.delete(delta.path) || raise NotFoundError.new("missing path: #{delta.path}")
        advance_version
      when FileDelta::Rename
        file = @files.delete(delta.old_path) || raise NotFoundError.new("missing path: #{delta.old_path}")
        if @files.has_key?(delta.new_path)
          raise ArgumentError.new("path already exists: #{delta.new_path}")
        end
        file.path = delta.new_path
        @files[delta.new_path] = file
        advance_version
      when FileDelta::SetMode
        file = required_file(delta.path)
        file.kind = delta.mode
        unless delta.mode.file?
          file.text = nil
          file.blob = nil
        end
        advance_version
      when FileDelta::SetLineEndings
        file = required_file(delta.path)
        file.line_ending = delta.line_endings
        advance_version
      when FileDelta::CreateDir
        create(delta.path, mode: FileMode::Directory)
      when FileDelta::CreateSymlink
        if @files.has_key?(delta.path)
          raise ArgumentError.new("path already exists: #{delta.path}")
        end
        @files[delta.path] = Entry.new(delta.path, FileMode::Symlink, symlink_target: delta.target)
        advance_version
      end
    end

    def write(path : String, text : String) : Nil
      file = required_file(path)
      unless file.kind.file?
        raise ArgumentError.new("not a regular file: #{path}")
      end
      file.text = Text::LineEnding.normalize(text)
      file.blob = @blob_store.put(file.text.not_nil!.to_slice)
      advance_version
    end

    def read(path : String) : String?
      @files[path]?.try(&.text)
    end

    def blob(path : String) : BlobRef?
      required_file(path).blob
    end

    def snapshot : Snapshot
      Snapshot.new(@version, @files.values.sort_by(&.path).map(&.copy))
    end

    def restore(snapshot : Snapshot) : Nil
      @seal_state.ensure_mutable!
      @files = {} of String => Entry
      snapshot.files.each { |file| @files[file.path] = file.copy }
      @version = snapshot.version
      @next_ordinal = (@version.ids.max_of?(&.ordinal) || 0u64) + 1u64
    end

    def seal : Nil
      @seal_state.seal(@version)
    end

    def sealed? : Bool
      @seal_state.sealed?
    end

    private def required_file(path : String) : Entry
      @files.fetch(path) { raise NotFoundError.new("missing path: #{path}") }
    end

    private def advance_version : Nil
      @version = @version.union(DeltaBatchId.new(@timeline.uuid, @next_ordinal))
      @next_ordinal += 1u64
    end
  end
end
