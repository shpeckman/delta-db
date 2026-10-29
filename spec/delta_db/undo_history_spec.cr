# spec/delta_db/undo_history_spec.cr
require "../spec_helper"

describe DeltaDB::UndoHistory do
  it "tracks transactions and undo/redo" do
    history = DeltaDB::UndoHistory.new(DeltaDB::Rope.build("base"))
    clock = DeltaDB::Clock.new

    id = history.start_transaction(clock)
    id.should_not be_nil

    ts = clock.tick
    op = DeltaDB::EditOperation.new(ts, DeltaDB::Global.new, [0u32..0u32], ["x"])
    history.push(op)
    history.push_undo(ts)

    entry = history.end_transaction
    entry.should_not be_nil
    entry.not_nil!.transaction.edit_ids.should eq [ts]
    history.operations[ts].should eq op

    history.undo_depth.should eq 1
    undone = history.undo
    undone.should_not be_nil
    history.undo_depth.should eq 0
    history.redo_depth.should eq 1

    redone = history.redo
    redone.should_not be_nil
    history.undo_depth.should eq 1
    history.redo_depth.should eq 0
  end

  it "drops empty transactions on end" do
    history = DeltaDB::UndoHistory.new(DeltaDB::Rope.build("base"))
    clock = DeltaDB::Clock.new
    history.start_transaction(clock)
    entry = history.end_transaction
    entry.should be_nil
    history.undo_depth.should eq 0
  end

  it "supports nested transactions" do
    history = DeltaDB::UndoHistory.new(DeltaDB::Rope.build("base"))
    clock = DeltaDB::Clock.new
    history.start_transaction(clock).should_not be_nil
    history.start_transaction(clock).should be_nil # nested returns nil
    history.end_transaction.should be_nil
    history.end_transaction.should be_nil # empty transaction dropped
  end
end
