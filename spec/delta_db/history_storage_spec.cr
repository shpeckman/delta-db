# spec/delta_db/history_storage_spec.cr
require "../spec_helper"

private def storage_timeline(number : UInt64, generation : UInt32 = 0u32) : DeltaDB::TimelineId
  DeltaDB::TimelineId.new(UUID.new("00000000-0000-0000-0000-#{number.to_s.rjust(12, '0')}"), generation)
end

private def storage_batch(timeline : DeltaDB::TimelineId, ordinal : UInt64, parents : DeltaDB::HistoryVersion = DeltaDB::HistoryVersion.new, epoch : UInt64 = 0u64) : DeltaDB::History::Batch
  DeltaDB::History::Batch.new(
    DeltaDB::DeltaBatchId.new(timeline.uuid, ordinal),
    timeline,
    DeltaDB::ActorUuid.new(timeline.uuid),
    parents,
    [] of DeltaDB::Delta,
    epoch,
  )
end

private def storage_version(*ids : DeltaDB::DeltaBatchId) : DeltaDB::HistoryVersion
  DeltaDB::HistoryVersion.from_ids(ids.to_a)
end

private def populated_dag(history : DeltaDB::HistoryId) : DeltaDB::History::Dag
  dag = DeltaDB::History::Dag.new(history)
  timeline = storage_timeline(1u64)
  other = storage_timeline(2u64)
  root = storage_batch(timeline, 1u64)
  left = storage_batch(timeline, 2u64, storage_version(root.id), 1u64)
  right = storage_batch(other, 3u64, storage_version(root.id), 1u64)
  merge = storage_batch(timeline, 4u64, storage_version(left.id, right.id), 1u64)
  dag.insert_on_timeline(root)
  dag.insert_on_timeline(left)
  dag.insert_on_timeline(right)
  dag.insert_on_timeline(merge)
  dag.begin_epoch
  dag
end

describe "history DAG storage" do
  it "round-trips batches, timelines, epochs, and checkpoint state" do
    storage = DeltaDB::Storage.in_memory
    history = DeltaDB::HistoryId.random
    dag = populated_dag(history)

    storage.save_dag(dag)
    loaded = storage.load_dag(history)

    loaded.batches.keys.sort.should eq dag.batches.keys.sort
    loaded.timeline_ids.should eq dag.timeline_ids
    loaded.timeline_version.should eq dag.timeline_version
    loaded.epochs.map(&.epoch).should eq dag.epochs.map(&.epoch)
    loaded.max_timestamp.should eq dag.max_timestamp
    loaded.epoch_count.should eq dag.epoch_count
    storage.checkpoint_version(history).should eq dag.timeline_version
  end

  it "installs checkpoint snapshots idempotently" do
    source = populated_dag(DeltaDB::HistoryId.random)
    storage = DeltaDB::Storage.in_memory
    snapshot = source.checkpoint

    storage.install_checkpoint(snapshot)
    storage.install_checkpoint(snapshot)
    loaded = storage.load_dag(source.history_id)

    loaded.batches.size.should eq source.batches.size
    loaded.timeline_version.should eq source.timeline_version
    loaded.common_ancestor(source.timeline_version, source.timeline_version).should eq source.timeline_version
    storage.db.scalar("SELECT COUNT(*) FROM history_delta_batches").should eq source.batches.size
  end

  it "reads packed delta values" do
    storage = DeltaDB::Storage.in_memory
    history = DeltaDB::HistoryId.random
    timeline = storage_timeline(1u64)
    actor = DeltaDB::ActorUuid.random
    first_timestamp = DeltaDB::Lamport.new(DeltaDB::ReplicaId::LOCAL, 10u32)
    second_timestamp = DeltaDB::Lamport.new(DeltaDB::ReplicaId::LOCAL, 11u32)
    first = DeltaDB::Delta.new(history, timeline, actor, first_timestamp, "first".to_slice)
    second = DeltaDB::Delta.new(history, timeline, actor, second_timestamp, "second value".to_slice)

    storage.pack_deltas(history, [first, second])

    storage.delta_value(history, first_timestamp).should eq "first".to_slice
    storage.delta_value(history, second_timestamp).should eq "second value".to_slice
    storage.db.scalar("SELECT COUNT(*) FROM history_delta_value_packs").should eq 1
  end

  it "persists delta runs" do
    storage = DeltaDB::Storage.in_memory
    history = DeltaDB::HistoryId.random
    replica = DeltaDB::ReplicaId.new(4u16)
    timestamp = DeltaDB::Lamport.new(replica, 7u32)
    ids = [DeltaDB::DeltaId.random, DeltaDB::DeltaId.random]

    storage.append_run(history, DeltaDB::DeltaRun.new(replica, timestamp, ids))
    runs = storage.load_runs(history)

    runs.size.should eq 1
    runs.first.actor.should eq replica
    runs.first.timestamp.should eq timestamp
    runs.first.delta_ids.should eq ids
  end

  it "round-trips timeline reset and fork metadata" do
    storage = DeltaDB::Storage.in_memory
    history = DeltaDB::HistoryId.random
    dag = DeltaDB::History::Dag.new(history)
    timeline = storage_timeline(1u64)
    root = storage_batch(timeline, 1u64)
    dag.insert_on_timeline(root)
    forked = dag.fork_timeline(timeline, storage_timeline(2u64))
    reset = dag.reset_timeline(timeline, storage_version(root.id))

    storage.save_dag(dag)
    loaded = storage.load_dag(history)

    loaded.timeline_parent_id(forked.id).should eq timeline
    loaded.timeline_parent_id(reset).should eq timeline
    loaded.timeline_lineage(reset).should eq [reset, timeline]
    loaded.timeline_version(forked.id).should eq storage_version(root.id)
    loaded.timeline_version(reset).should eq storage_version(root.id)
  end

  it "migrates new databases and rejects newer schemas" do
    storage = DeltaDB::Storage.in_memory
    storage.schema_version.should eq DeltaDB::Storage::CURRENT_SCHEMA_VERSION
    storage.schema_version = DeltaDB::Storage::CURRENT_SCHEMA_VERSION + 1

    expect_raises(ArgumentError) { DeltaDB::Storage.new(storage.db) }
  end
end
