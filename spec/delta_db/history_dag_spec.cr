# spec/delta_db/history_dag_spec.cr
require "../spec_helper"

private def spec_timeline(number : UInt64, generation : UInt32 = 0u32) : DeltaDB::TimelineId
  DeltaDB::TimelineId.new(UUID.new("00000000-0000-0000-0000-#{number.to_s.rjust(12, '0')}"), generation)
end

private def spec_batch(timeline : DeltaDB::TimelineId, ordinal : UInt64, parents : DeltaDB::HistoryVersion = DeltaDB::HistoryVersion.new, epoch : UInt64 = 0u64) : DeltaDB::History::Batch
  DeltaDB::History::Batch.new(
    DeltaDB::DeltaBatchId.new(timeline.uuid, ordinal),
    timeline,
    DeltaDB::ActorUuid.new(timeline.uuid),
    parents,
    [] of DeltaDB::Delta,
    epoch,
  )
end

private def version_of(*ids : DeltaDB::DeltaBatchId) : DeltaDB::HistoryVersion
  DeltaDB::HistoryVersion.from_ids(ids.to_a)
end

describe DeltaDB::History::Dag do
  it "walks ancestry and computes maximal common ancestors" do
    history = DeltaDB::HistoryId.random
    dag = DeltaDB::History::Dag.new(history)
    timeline = spec_timeline(1u64)
    other = spec_timeline(2u64)
    root = spec_batch(timeline, 1u64)
    left = spec_batch(timeline, 2u64, version_of(root.id))
    right = spec_batch(other, 3u64, version_of(root.id))
    merge = spec_batch(timeline, 4u64, version_of(left.id, right.id))
    dag.insert_on_timeline(root)
    dag.insert_on_timeline(left)
    dag.insert_on_timeline(right)
    dag.insert_on_timeline(merge)

    dag.ancestors(version_of(merge.id)).ids.should eq [root.id, left.id, right.id, merge.id].sort
    dag.version_reaches(version_of(root.id), version_of(merge.id)).should be_true
    dag.version_reaches(version_of(left.id), version_of(right.id)).should be_false
    dag.common_ancestor(version_of(left.id), version_of(right.id)).should eq version_of(root.id)
    dag.dominator(version_of(merge.id), version_of(right.id)).should eq version_of(right.id)
    DeltaDB::History::MergeBase.resolve(dag, version_of(left.id), version_of(right.id)).should eq version_of(root.id)
    dag.delta_headers_difference(version_of(merge.id), version_of(root.id)).map(&.id).should eq [left.id, right.id, merge.id].sort
    dag.contains_version(version_of(root.id, merge.id)).should be_true
    dag.contains_version(version_of(root.id), timeline).should be_true
  end

  it "supports timeline reset, fork, lineage, and epochs" do
    dag = DeltaDB::History::Dag.new(DeltaDB::HistoryId.random)
    timeline = spec_timeline(1u64)
    root = spec_batch(timeline, 1u64)
    dag.insert_on_timeline(root)
    forked = dag.fork_timeline(timeline, spec_timeline(2u64))
    forked.head.should eq version_of(root.id)

    reset = dag.reset_timeline(timeline, version_of(root.id))
    reset.generation.should eq 1u32
    dag.timeline_lineage(reset).should eq [reset, timeline]
    dag.timeline_parent_id(forked.id).should eq timeline

    epoch = dag.begin_epoch
    epoch.epoch.should eq 1u64
    epoch.start_version.ids.should contain root.id
    next_batch = spec_batch(reset, 2u64, version_of(root.id), 1u64)
    dag.insert_on_timeline(next_batch)
    dag.epoch_of_version(version_of(next_batch.id)).should eq 1u64
    dag.common_ancestor_since_epoch(version_of(next_batch.id), version_of(root.id), 1u64).empty?.should be_true
  end

  it "round-trips checkpoint DAG state and rejects missing parents" do
    dag = DeltaDB::History::Dag.new(DeltaDB::HistoryId.random)
    timeline = spec_timeline(1u64)
    root = spec_batch(timeline, 1u64)
    child = spec_batch(timeline, 2u64, version_of(root.id), 2u64)
    dag.insert_on_timeline(root)
    dag.insert_on_timeline(child)
    dag.begin_epoch

    restored = DeltaDB::History::Dag.from_snapshot(dag.checkpoint)
    restored.timeline_version(timeline).should eq dag.timeline_version(timeline)
    restored.batches.keys.sort.should eq dag.batches.keys.sort
    restored.epoch_count.should eq dag.epoch_count
    restored.common_ancestor(version_of(child.id), version_of(root.id)).should eq version_of(root.id)

    orphan = spec_batch(spec_timeline(3u64), 9u64, version_of(root.id, DeltaDB::DeltaBatchId.new(spec_timeline(9u64).uuid, 99u64)))
    expect_raises(ArgumentError) { dag.insert_globally(orphan) }
  end
end
