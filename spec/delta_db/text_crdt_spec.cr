# spec/delta_db/text_crdt_spec.cr
require "../spec_helper"

private def new_buffer(replica : UInt16 = 0u16, text : String = "") : DeltaDB::Text::Buffer
  DeltaDB::Text::Buffer.new(DeltaDB::ReplicaId.new(replica), DeltaDB::Text::BufferId.new(1u64), text)
end

describe DeltaDB::Text::Buffer do
  it "maintains visible and deleted text through replacements" do
    buffer = new_buffer(text: "abc")
    buffer.edit([{1...2, "X"}])

    buffer.text.should eq "aXc"
    buffer.snapshot.deleted.should eq "b"
    buffer.snapshot.fragments.map(&.text).join.should eq "aXbc"
    buffer.check_invariants

    buffer.edit([{1...2, ""}])
    buffer.text.should eq "ac"
    buffer.snapshot.deleted.should eq "Xb"
    buffer.check_invariants
  end

  it "resolves anchors through insertions and deletions" do
    buffer = new_buffer
    buffer.edit([{0...0, "abc"}])
    left = buffer.anchor_before(2)
    right = buffer.anchor_after(2)

    buffer.edit([{1...1, "def\n"}])
    buffer.snapshot.offset_for_anchor(left).should eq 6
    buffer.snapshot.offset_for_anchor(right).should eq 6

    buffer.edit([{2...3, ""}])
    buffer.snapshot.offset_for_anchor(left).should eq 5
    buffer.snapshot.offset_for_anchor(right).should eq 5

    buffer.edit([{5...5, "ghi\n"}])
    buffer.snapshot.offset_for_anchor(left).should eq 5
    buffer.snapshot.offset_for_anchor(right).should eq 9

    buffer.edit([{7...9, ""}])
    buffer.text.should eq "adf\nbghc"
    buffer.snapshot.offset_for_anchor(left).should eq 5
    buffer.snapshot.offset_for_anchor(right).should eq 7
    buffer.check_invariants
  end

  it "keeps start and end anchors stable" do
    buffer = new_buffer
    before_start = buffer.anchor_before(0)
    after_end = buffer.anchor_after(0)
    buffer.edit([{0...0, "abc"}])
    after_start = buffer.anchor_after(0)
    before_end = buffer.anchor_before(3)

    buffer.edit([{3...3, "def"}])
    buffer.edit([{0...0, "ghi"}])

    buffer.snapshot.offset_for_anchor(before_start).should eq 0
    buffer.snapshot.offset_for_anchor(after_start).should eq 3
    buffer.snapshot.offset_for_anchor(before_end).should eq 6
    buffer.snapshot.offset_for_anchor(after_end).should eq 9
  end

  it "generates and applies undo and redo operations" do
    buffer = new_buffer(text: "1234")
    buffer.edit([{1...1, "abx"}])
    first = buffer.history.peek_undo_stack.not_nil!.transaction
    buffer.edit([{3...4, "yzef"}])
    second = buffer.history.peek_undo_stack.not_nil!.transaction
    buffer.edit([{3...5, "cd"}])
    third = buffer.history.peek_undo_stack.not_nil!.transaction
    buffer.text.should eq "1abcdef234"

    buffer.undo_or_redo(first)
    buffer.text.should eq "1cdef234"
    buffer.undo_or_redo(first)
    buffer.text.should eq "1abcdef234"
    buffer.undo_or_redo(second)
    buffer.text.should eq "1abcdx234"
    buffer.undo_or_redo(third)
    buffer.text.should eq "1abx234"
    buffer.undo_or_redo(second)
    buffer.text.should eq "1abyzef234"
    buffer.undo_or_redo(third)
    buffer.text.should eq "1abcdef234"
    buffer.undo_or_redo(third)
    buffer.text.should eq "1abyzef234"
    buffer.undo_or_redo(first)
    buffer.text.should eq "1yzef234"
    buffer.undo_or_redo(second)
    buffer.text.should eq "1234"
    buffer.check_invariants
  end

  it "converges concurrent and duplicate edits" do
    one = new_buffer(1u16, "abcdef")
    two = new_buffer(2u16, "abcdef")
    three = new_buffer(3u16, "abcdef")
    first = one.edit([{1...2, "12"}])
    second = two.edit([{3...4, "34"}])
    third = three.edit([{5...6, "56"}])

    one.apply_ops([third, second, second])
    two.apply_ops([third, first, first])
    three.apply_ops([second, first])

    one.text.should eq "a12c34e56"
    two.text.should eq one.text
    three.text.should eq one.text
    one.check_invariants
    two.check_invariants
    three.check_invariants
  end

  it "defers operations until causal dependencies arrive" do
    one = new_buffer(1u16, "abc")
    two = new_buffer(2u16, "abc")
    first = one.edit([{1...2, "X"}])
    second = one.edit([{3...3, "Y"}])

    two.apply(second)
    two.text.should eq "abc"
    two.deferred_ops_count.should eq 1
    two.apply(first)
    two.text.should eq one.text
    two.deferred_ops_count.should eq 0
    undo = one.undo.not_nil!
    three = new_buffer(3u16, "abc")
    three.apply(undo)
    three.deferred_ops_count.should eq 1
    three.apply_ops([second, first])
    three.text.should eq "aXc"
    three.deferred_ops_count.should eq 0
    three.check_invariants
  end

  it "handles edits partially intersecting deleted fragments" do
    buffer = new_buffer(1u16, "abcdefgh")
    buffer.edit([{2...5, ""}])
    timestamp = DeltaDB::Lamport.new(DeltaDB::ReplicaId.new(2u16), 10u32)
    operation = DeltaDB::Text::EditOperation.new(timestamp, buffer.version, [1u32...4u32], [""])

    buffer.apply(operation)
    buffer.text.should eq "afgh"
    buffer.undo_operations({timestamp => UInt32::MAX})
    buffer.text.should eq "abfgh"
    buffer.check_invariants
  end

  it "converges with duplicate out-of-order network delivery" do
    replica_ids = Array.new(4) { |index| DeltaDB::ReplicaId.new(index.to_u16) }
    buffers = replica_ids.map { |id| new_buffer(id.value, "abcdef") }
    network = TestNetwork(DeltaDB::Text::Operation).new(42u64)
    replica_ids.each { |id| network.add_peer(id) }
    random = Random.new(7u64)

    24.times do
      index = random.rand(buffers.size)
      buffer = buffers[index]
      if random.rand(4) == 0 && buffer.history.undo_depth > 0
        if operation = buffer.undo
          network.broadcast(buffer.replica_id, [operation.as(DeltaDB::Text::Operation)])
        end
      else
        start = random.rand(buffer.bytesize + 1)
        finish = start + random.rand(buffer.bytesize - start + 1)
        replacement = ["X", "yz", "", "Q"][random.rand(4)]
        operation = buffer.edit([{start...finish, replacement}])
        network.broadcast(buffer.replica_id, [operation.as(DeltaDB::Text::Operation)])
      end

      if random.rand(2) == 0
        receiver = random.rand(buffers.size)
        buffers[receiver].apply_ops(network.receive(replica_ids[receiver]))
      end
      buffer.check_invariants
    end

    until network.idle?
      receiver = random.rand(buffers.size)
      buffers[receiver].apply_ops(network.receive(replica_ids[receiver]))
    end

    expected = buffers.first.text
    buffers.each do |buffer|
      buffer.text.should eq expected
      buffer.check_invariants
    end
  end
end
