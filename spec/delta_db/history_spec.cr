# spec/delta_db/history_spec.cr
require "../spec_helper"

describe "history engine" do
  it "constructs a delta run and history record" do
    run = DeltaDB::Storage::Run.new(
      DeltaDB::ReplicaId::LOCAL,
      DeltaDB::Lamport.new(DeltaDB::ReplicaId::LOCAL, 1u32),
      [DeltaDB::DeltaId.random],
    )
    run.delta_ids.size.should eq 1

    uuid = UUID.random
    version = DeltaDB::History::Version.from_id(DeltaDB::DeltaBatchId.new(uuid, 0u64))
    record = DeltaDB::History::Record.new(DeltaDB::HistoryId.random, DeltaDB::TimelineId.random, version)
    record.target_version.should eq version
  end

  it "resolves a merge base for identical versions" do
    uuid = UUID.random
    v = DeltaDB::History::Version.from_id(DeltaDB::DeltaBatchId.new(uuid, 0u64))
    DeltaDB::History::MergeBase.resolve(v, v).should eq v
  end
end
