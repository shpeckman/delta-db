require "../spec_helper"

private def make_delta(timeline : DeltaDB::TimelineId, value : String, parent : DeltaDB::DeltaId? = nil) : DeltaDB::Delta
  DeltaDB::Delta.new(
    DeltaDB::DeltaId.random,
    timeline,
    parent,
    DeltaDB::ActorUuid.random,
    DeltaDB::Lamport.new(DeltaDB::ReplicaId::LOCAL, 1u32),
    value.to_slice,
  )
end

describe DeltaDB::Storage do
  it "round-trips a small delta value" do
    storage = DeltaDB::Storage.in_memory
    timeline = DeltaDB::TimelineId.random
    delta = make_delta(timeline, "hello world")
    storage.insert_delta(delta)
    storage.delta_value(delta.id).should eq "hello world".to_slice
  end

  it "round-trips a large delta value via overflow chunks" do
    storage = DeltaDB::Storage.in_memory
    timeline = DeltaDB::TimelineId.random
    value = "x" * 1000
    delta = make_delta(timeline, value)
    storage.insert_delta(delta)
    storage.delta_value(delta.id).should eq value.to_slice
  end

  it "reads back a delta header with reassembled value" do
    storage = DeltaDB::Storage.in_memory
    timeline = DeltaDB::TimelineId.random
    value = "y" * 50
    delta = make_delta(timeline, value)
    storage.insert_delta(delta)
    header = storage.delta_header(delta.id)
    header.should_not be_nil
    header.not_nil!.value.should eq value.to_slice
    header.not_nil!.timeline_id.should eq timeline
  end

  it "assigns monotonic versions and advances the timeline head" do
    storage = DeltaDB::Storage.in_memory
    timeline = DeltaDB::TimelineId.random
    history = DeltaDB::HistoryId.random
    storage.ensure_timeline(timeline, history)

    d1 = make_delta(timeline, "first")
    d2 = make_delta(timeline, "second", d1.id)
    d3 = make_delta(timeline, "third", d2.id)

    v1 = storage.append_delta(d1)
    v2 = storage.append_delta(d2)
    v3 = storage.append_delta(d3)

    v1.value.should eq 0u64
    v2.value.should eq 1u64
    v3.value.should eq 2u64

    storage.timeline_head(timeline).should eq d3.id
    storage.delta_at_version(timeline, v1).should eq d1.id
    storage.delta_at_version(timeline, v3).should eq d3.id
  end

  it "stores and reads schema version" do
    storage = DeltaDB::Storage.in_memory
    storage.schema_version.should eq 0
    storage.schema_version = 3
    storage.schema_version.should eq 3
  end
end
