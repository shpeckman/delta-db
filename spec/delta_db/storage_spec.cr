# spec/delta_db/storage_spec.cr
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

private def stored_timeline_heads(storage : DeltaDB::Storage) : Hash(String, {String?, Int64?})
  rows = {} of String => {String?, Int64?}
  storage.db.query(
    "SELECT history_actors.actor, history_timelines.version, history_timelines.version_key " \
    "FROM history_timelines " \
    "JOIN history_actors ON history_actors.history_key = history_timelines.history_key " \
    "AND history_actors.actor_ordinal = history_timelines.timeline_actor",
  ) do |result_set|
    result_set.each do
      rows[result_set.read(String)] = {result_set.read(String?), result_set.read(Int64?)}
    end
  end
  rows
end

describe DeltaDB::Storage do
  it "round-trips a small delta value" do
    storage = DeltaDB::Storage.in_memory
    history = DeltaDB::HistoryId.random
    clock = DeltaDB::Clock.new
    delta = make_delta(history, DeltaDB::TimelineId.random, "hello world", clock.tick)
    storage.insert_delta(delta)
    storage.delta_value(history, delta.timestamp).should eq "hello world".to_slice
    storage.db.scalar("SELECT COUNT(*) FROM history_actors").should eq 1
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

  it "assigns timestamp-based batch ids and persists the timeline head" do
    storage = DeltaDB::Storage.in_memory
    history = DeltaDB::HistoryId.random
    timeline = DeltaDB::TimelineId.random
    clock = DeltaDB::Clock.new
    d1 = make_delta(history, timeline, "first", clock.tick)
    d2 = make_delta(history, timeline, "second", clock.tick)

    v1 = storage.append_delta(d1)
    v2 = storage.append_delta(d2)

    v1.ids.map(&.ordinal).should eq [1u64]
    v2.ids.map(&.ordinal).should eq [2u64]
    storage.db.scalar("SELECT COUNT(*) FROM history_versions").should eq 2
    storage.db.scalar("SELECT COUNT(*) FROM history_timelines").should eq 1
    storage.db.scalar("SELECT COUNT(*) FROM history_actors").should eq 3
    stored_timeline_heads(storage)[timeline.to_s][1].should eq 1i64
  end

  it "advances only the appended timeline" do
    storage = DeltaDB::Storage.in_memory
    history = DeltaDB::HistoryId.random
    first_timeline = DeltaDB::TimelineId.random
    second_timeline = DeltaDB::TimelineId.random
    clock = DeltaDB::Clock.new

    storage.append_delta(make_delta(history, first_timeline, "first", clock.tick))
    storage.append_delta(make_delta(history, second_timeline, "second", clock.tick))
    storage.append_delta(make_delta(history, first_timeline, "third", clock.tick))

    heads = stored_timeline_heads(storage)
    heads.size.should eq 2
    heads[first_timeline.to_s][1].should eq 2i64
    heads[second_timeline.to_s][1].should eq 1i64
    storage.db.scalar("SELECT COUNT(*) FROM history_actors").should eq 5
  end

  it "reuses actor ordinals across repeated registration" do
    storage = DeltaDB::Storage.in_memory
    history = DeltaDB::HistoryId.random
    actor = DeltaDB::ActorUuid.random

    storage.record_actor(history, actor)
    storage.record_actor(history, actor)

    storage.db.scalar("SELECT COUNT(*) FROM history_actors").should eq 1
    storage.db.scalar("SELECT actor_ordinal FROM history_actors").should eq 0i64
  end

  it "stores and reads schema version" do
    storage = DeltaDB::Storage.in_memory
    storage.schema_version.should eq DeltaDB::Storage::CURRENT_SCHEMA_VERSION
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
