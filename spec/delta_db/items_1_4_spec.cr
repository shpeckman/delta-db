# spec/delta_db/items_1_4_spec.cr
require "../spec_helper"

describe DeltaDB::Map do
  it "stores and retrieves register values" do
    map = DeltaDB::Map.new
    map.set("name", "delta")
    map.get("name").should eq "delta"
    map.get("missing").should be_nil
  end
end

describe DeltaDB::Replica do
  it "holds a value and ticks a Lamport clock" do
    map = DeltaDB::Map.new
    replica = DeltaDB::Replica(DeltaDB::Map).new(map)
    first = replica.tick
    first.value.should eq 1u32
    replica.tick.value.should eq 2u32
    replica.value.should eq map
  end
end

describe "history engine" do
  it "constructs a delta run and history record" do
    run = DeltaDB::DeltaRun.new(
      DeltaDB::ReplicaId::LOCAL,
      DeltaDB::Lamport.new(DeltaDB::ReplicaId::LOCAL, 1u32),
      [DeltaDB::DeltaId.random],
    )
    run.delta_ids.size.should eq 1

    uuid = UUID.random
    version = DeltaDB::HistoryVersion.from_id(DeltaDB::DeltaBatchId.new(uuid, 0u64))
    record = DeltaDB::History::Record.new(DeltaDB::HistoryId.random, DeltaDB::TimelineId.random, version)
    record.target_version.should eq version
  end

  it "resolves a merge base for identical versions" do
    uuid = UUID.random
    v = DeltaDB::HistoryVersion.from_id(DeltaDB::DeltaBatchId.new(uuid, 0u64))
    DeltaDB::History::MergeBase.resolve(v, v).should eq v
  end
end
