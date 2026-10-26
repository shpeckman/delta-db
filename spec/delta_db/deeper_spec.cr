require "../spec_helper"

describe DeltaDB::EditTopic do
  it "publishes to subscribers until cancelled" do
    topic = DeltaDB::EditTopic(Int32).new
    received = [] of Int32
    sub = topic.subscribe { |v| received << v }

    topic.publish(1)
    topic.publish(2)
    received.should eq [1, 2]

    sub.cancel
    topic.publish(3)
    received.should eq [1, 2]
  end
end

describe DeltaDB::FileReadDiagnostics do
  it "loads a file blob with diagnostics" do
    path = File.tempname("delta-test", ".txt")
    begin
      File.write(path, "hello world")
      result = DeltaDB::FileReadDiagnostics.load_file_blob(path)
      result.should_not be_nil
      bytes, diag = result.not_nil!
      bytes.should eq "hello world".to_slice
      diag.path.should eq path
      diag.bytes.should eq 11u64
    ensure
      File.delete(path) if File.exists?(path)
    end
  end

  it "does not warn for fast reads" do
    diag = DeltaDB::FileReadDiagnostics.new("/tmp/x", 10u64, 1.millisecond)
    DeltaDB::FileReadDiagnostics.warn_if_read_slow(diag) # no-op, no exception
  end
end

describe "file tree state" do
  it "orders InodeId and distinguishes entry kinds" do
    (DeltaDB::InodeId.new(1u64) < DeltaDB::InodeId.new(2u64)).should be_true
    DeltaDB::FileTreeEntryKind::File.should_not eq DeltaDB::FileTreeEntryKind::Directory
    DeltaDB::FileTreeEntryKind::Symlink.should_not eq DeltaDB::FileTreeEntryKind::Directory
  end
end

describe "fragment index model" do
  it "validates edit ranges" do
    DeltaDB.validate_edit_ranges([0u32..2u32, 3u32..5u32]).should be_true
    DeltaDB.validate_edit_ranges([0u32..5u32, 3u32..7u32]).should be_false
  end

  it "constructs aliases, splices, and applied edits" do
    id = DeltaDB::FragmentId.random
    alias_span = DeltaDB::AliasSpan.new(0u32, 10u32)
    alias_span.end.should eq 10u32

    splice = DeltaDB::ContentSplice.new(2u32..5u32, "new")
    splice.text.should eq "new"

    applied = DeltaDB::AppliedFragmentEdit.new(id, 0u32..3u32, "x")
    applied.fragment_id.should eq id
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
