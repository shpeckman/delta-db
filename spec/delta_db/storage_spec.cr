require "../spec_helper"

private def make_delta(history : DeltaDB::HistoryId, timeline : DeltaDB::TimelineId, value : String, timestamp : DeltaDB::Lamport) : DeltaDB::Delta
  DeltaDB::Delta.new(
    history,
    timeline,
    DeltaDB::ActorUuid.random,
    timestamp,
    value.to_slice,
  )
end

describe DeltaDB::Storage do
  it "round-trips a small delta value" do
    storage = DeltaDB::Storage.in_memory
    history = DeltaDB::HistoryId.random
    clock = DeltaDB::Clock.new
    delta = make_delta(history, DeltaDB::TimelineId.random, "hello world", clock.tick)
    storage.insert_delta(delta)
    storage.delta_value(history, delta.timestamp).should eq "hello world".to_slice
  end

  it "round-trips a large delta value via overflow chunks" do
    storage = DeltaDB::Storage.in_memory
    history = DeltaDB::HistoryId.random
    clock = DeltaDB::Clock.new
    value = "x" * 1000
    delta = make_delta(history, DeltaDB::TimelineId.random, value, clock.tick)
    storage.insert_delta(delta)
    storage.delta_value(history, delta.timestamp).should eq value.to_slice
  end

  it "assigns monotonic versions on append" do
    storage = DeltaDB::Storage.in_memory
    history = DeltaDB::HistoryId.random
    timeline = DeltaDB::TimelineId.random
    clock = DeltaDB::Clock.new
    d1 = make_delta(history, timeline, "first", clock.tick)
    d2 = make_delta(history, timeline, "second", clock.tick)

    v1 = storage.append_delta(d1)
    v2 = storage.append_delta(d2)

    v1.batch_id.ordinal.should eq 0u64
    v2.batch_id.ordinal.should eq 1u64
    (v1 < v2).should be_true
  end

  it "stores and reads schema version" do
    storage = DeltaDB::Storage.in_memory
    storage.schema_version.should eq 0
    storage.schema_version = 3
    storage.schema_version.should eq 3
  end

  it "resolves a stable integer history_key and stores the uuid blob" do
    storage = DeltaDB::Storage.in_memory
    history = DeltaDB::HistoryId.random
    key = storage.history_key_for(history)
    key.should be >= 0
    storage.history_key_for(history).should eq key
  end
end
