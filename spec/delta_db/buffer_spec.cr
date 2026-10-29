# spec/delta_db/buffer_spec.cr
require "../spec_helper"

describe DeltaDB::Selection do
  it "reports head/tail for reversed and forward selections" do
    sel = DeltaDB::Selection(Int32).new(1, 2, 5, false, DeltaDB::SelectionGoal::None)
    sel.head.should eq 5
    sel.tail.should eq 2
    sel.range.should eq 2..5

    rev = DeltaDB::Selection(Int32).new(1, 2, 5, true, DeltaDB::SelectionGoal::None)
    rev.head.should eq 2
    rev.tail.should eq 5
  end

  it "builds an empty selection from an offset" do
    sel = DeltaDB::Selection(Int32).from_offset(7)
    sel.start.should eq 7
    sel.end.should eq 7
    sel.range.should eq 7..7
  end
end

describe DeltaDB::Edit do
  it "reports empty and lengths" do
    edit = DeltaDB::Edit(Int32).new(2..2, 2..2)
    edit.empty?.should be_true

    edit = DeltaDB::Edit(Int32).new(2..5, 2..9)
    edit.old_size.should eq 3
    edit.new_size.should eq 7
  end
end

describe DeltaDB::UndoMap do
  it "reports undone when the undo count is odd" do
    edit_id = DeltaDB::Lamport.new(DeltaDB::ReplicaId::LOCAL, 1u32)
    undo = DeltaDB::UndoOperation.new(
      DeltaDB::Lamport.new(DeltaDB::ReplicaId::LOCAL, 2u32),
      DeltaDB::Global.new,
      {edit_id => 1u32},
    )
    map = DeltaDB::UndoMap.new
    map.undone?(edit_id).should be_false
    map.insert(undo)
    map.undone?(edit_id).should be_true

    map.insert(undo)
    map.undo_count(edit_id).should eq 1u32
  end
end

describe DeltaDB::BufferSnapshot do
  it "builds from text" do
    buffer_id = DeltaDB::BufferId.new(1u64)
    snapshot = DeltaDB::BufferSnapshot.build("hello", buffer_id)
    snapshot.text.should eq "hello"
    snapshot.bytesize.should eq 5
    snapshot.empty?.should be_false
  end

  it "applies edits and observes the version" do
    buffer_id = DeltaDB::BufferId.new(1u64)
    snapshot = DeltaDB::BufferSnapshot.build("hello world", buffer_id)

    ts = DeltaDB::Lamport.new(DeltaDB::ReplicaId::LOCAL, 5u32)
    op = DeltaDB::EditOperation.new(ts, snapshot.version.clone, [6u32..11u32], ["there"])
    snapshot.edit([op])

    snapshot.text.should eq "hello there"
    snapshot.version.observed?(ts).should be_true
  end

  it "resolves an anchor to an offset" do
    buffer_id = DeltaDB::BufferId.new(1u64)
    snapshot = DeltaDB::BufferSnapshot.build("hello", buffer_id)
    anchor = DeltaDB::Anchor.new(DeltaDB::Lamport.new(DeltaDB::ReplicaId::LOCAL, 1u32), 3u32, DeltaDB::Bias::Left, buffer_id)
    snapshot.offset_for_anchor(anchor).should eq 3
  end
end
