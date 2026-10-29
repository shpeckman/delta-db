# spec/delta_db/patch_spec.cr
require "../spec_helper"

private struct TestOp
  getter ts : DeltaDB::Lamport

  def initialize(@ts : DeltaDB::Lamport)
  end
end

describe DeltaDB::Text::Patch do
  it "translates old positions through a patch" do
    patch = DeltaDB::Text::Patch(Int32).new([DeltaDB::Text::Edit(Int32).new(2..5, 2..9)])
    patch.old_to_new(0).should eq 0
    patch.old_to_new(2).should eq 2
    patch.old_to_new(4).should eq 2
    patch.old_to_new(6).should eq 10
  end

  it "inverts by swapping old/new" do
    patch = DeltaDB::Text::Patch(Int32).new([DeltaDB::Text::Edit(Int32).new(2..5, 2..9)])
    patch.invert!
    patch.edits.first.old.should eq 2..9
    patch.edits.first.new.should eq 2..5
  end

  it "merges adjacent edits on push" do
    patch = DeltaDB::Text::Patch(Int32).empty
    patch.push(DeltaDB::Text::Edit(Int32).new(0..3, 0..3))
    patch.push(DeltaDB::Text::Edit(Int32).new(3..5, 3..5))
    patch.edits.size.should eq 1
    patch.edits.first.old.should eq 0..5
  end

  it "composes with no new edits as identity" do
    patch = DeltaDB::Text::Patch(Int32).new([DeltaDB::Text::Edit(Int32).new(2..5, 2..9)])
    composed = patch.compose([] of DeltaDB::Text::Edit(Int32))
    composed.edits.should eq patch.edits
  end

  it "composes disjoint new edits after existing edits" do
    patch = DeltaDB::Text::Patch(Int32).new([DeltaDB::Text::Edit(Int32).new(0..3, 0..3)])
    composed = patch.compose([DeltaDB::Text::Edit(Int32).new(10..12, 10..15)])
    composed.edits.size.should eq 2
  end
end

describe DeltaDB::OperationQueue do
  it "inserts, deduplicates, and drains" do
    queue = DeltaDB::OperationQueue(TestOp).new
    clock = DeltaDB::Clock.new
    queue.insert([TestOp.new(clock.tick), TestOp.new(clock.tick)]) { |op| op.ts }
    queue.size.should eq 2

    queue.insert([TestOp.new(clock.tick)]) { |op| op.ts }
    queue.size.should eq 3

    drained = queue.drain
    drained.size.should eq 3
    queue.size.should eq 0
    queue.empty?.should be_true
  end
end

describe TestNetwork do
  it "broadcasts and receives messages" do
    net = TestNetwork(String).new(42u64)
    a = DeltaDB::ReplicaId.new(0u16)
    b = DeltaDB::ReplicaId.new(1u16)
    net.add_peer(a)
    net.add_peer(b)

    net.broadcast(a, ["hi", "there"])
    net.has_unreceived?(a).should be_false
    net.has_unreceived?(b).should be_true
    received = [] of String
    until net.idle?
      received.concat(net.receive(b))
    end
    received.should contain "hi"
    received.should contain "there"
  end

  it "drops broadcasts from disconnected peers" do
    net = TestNetwork(String).new
    a = DeltaDB::ReplicaId.new(0u16)
    b = DeltaDB::ReplicaId.new(1u16)
    net.add_peer(a)
    net.add_peer(b)
    net.disconnect_peer(a)
    net.broadcast(a, ["hi"])
    net.has_unreceived?(b).should be_false
  end
end
