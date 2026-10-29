# spec/delta_db/disk_worktree_fs_spec.cr
require "../spec_helper"

describe DeltaDB::Worktree::Disk do
  it "generates unique temp paths with the delta-fs prefix" do
    a = DeltaDB::Worktree::Disk.temp_file_path("/tmp")
    b = DeltaDB::Worktree::Disk.temp_file_path("/tmp")
    a.should_not eq b
    a.should contain(".delta-fs-")
    DeltaDB::Worktree::Disk.path_contains_temp_component(a).should be_true
    DeltaDB::Worktree::Disk.path_contains_temp_component("src/main.cr").should be_false
  end

  it "scans a directory into entries" do
    Dir.mkdir_p("/tmp/delta-db-scan-test/a")
    File.write("/tmp/delta-db-scan-test/file.txt", "x")
    begin
      entries = DeltaDB::Worktree::Disk.scan_directory("/tmp/delta-db-scan-test")
      entries.map(&.[0]).sort.should eq ["a", "file.txt"]
      kinds = entries.to_h
      kinds["a"].should eq DeltaDB::FileTreeEntryKind::Directory
      kinds["file.txt"].should eq DeltaDB::FileTreeEntryKind::File
    ensure
      DeltaDB::Worktree::Disk.remove_dir_all_clearing_permissions("/tmp/delta-db-scan-test")
    end
  end

  it "removes a directory tree even with read-only files" do
    Dir.mkdir_p("/tmp/delta-db-rm-test/sub")
    File.write("/tmp/delta-db-rm-test/sub/ro.txt", "x")
    File.chmod("/tmp/delta-db-rm-test/sub/ro.txt", 0o400)
    DeltaDB::Worktree::Disk.remove_dir_all_clearing_permissions("/tmp/delta-db-rm-test")
    Dir.exists?("/tmp/delta-db-rm-test").should be_false
  end
end
