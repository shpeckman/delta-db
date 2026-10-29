# spec/delta_db/file_tree_state_spec.cr
require "../spec_helper"

describe "file tree state" do
  it "orders InodeId and distinguishes entry kinds" do
    (DeltaDB::InodeId.new(1u64) < DeltaDB::InodeId.new(2u64)).should be_true
    DeltaDB::FileTreeEntryKind::File.should_not eq DeltaDB::FileTreeEntryKind::Directory
    DeltaDB::FileTreeEntryKind::Symlink.should_not eq DeltaDB::FileTreeEntryKind::Directory
  end
end

describe "file tree state model" do
  it "constructs inodes and edges" do
    parent = DeltaDB::InodeId.new(1u64)
    child = DeltaDB::InodeId.new(2u64)
    edge = DeltaDB::ChildEdge.new(parent, child, "sub")
    edge.parent.should eq parent
    edge.name.should eq "sub"

    symlink = DeltaDB::Inode.new(child, DeltaDB::FileTreeEntryKind::Symlink, DeltaDB::SymlinkPayload.new("target"))
    symlink.kind.should eq DeltaDB::FileTreeEntryKind::Symlink
  end
end
