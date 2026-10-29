# src/delta_db/file_mode.cr
module DeltaDB
  enum FileMode
    File
    Directory
    Symlink
  end
end
