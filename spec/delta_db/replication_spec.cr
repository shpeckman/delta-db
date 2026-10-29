# spec/delta_db/replication_spec.cr
require "../spec_helper"

private def replication_timeline(number : UInt64, generation : UInt32 = 0u32) : DeltaDB::TimelineId
  DeltaDB::TimelineId.new(UUID.new("00000000-0000-0000-0000-#{number.to_s.rjust(12, '0')}"), generation)
end

private def replication_version(*ids : DeltaDB::DeltaBatchId) : DeltaDB::History::Version
  DeltaDB::History::Version.from_ids(ids.to_a)
end

private def replication_batch(timeline : DeltaDB::TimelineId, ordinal : UInt64, parents : DeltaDB::History::Version = DeltaDB::History::Version.new, epoch : UInt64 = 0u64) : DeltaDB::History::Batch
  DeltaDB::History::Batch.new(
    DeltaDB::DeltaBatchId.new(timeline.uuid, ordinal),
    timeline,
    DeltaDB::ActorUuid.new(timeline.uuid),
    parents,
    [] of DeltaDB::Delta,
    epoch,
  )
end

private def replication_dag(history : DeltaDB::HistoryId) : DeltaDB::History::Dag
  dag = DeltaDB::History::Dag.new(history)
  timeline = replication_timeline(1u64)
  root = replication_batch(timeline, 1u64)
  delta = DeltaDB::Delta.new(history, timeline, root.actor, DeltaDB::Lamport.new(DeltaDB::ReplicaId::LOCAL, 1u32), Bytes[0u8, 1u8, 255u8])
  root = DeltaDB::History::Batch.new(root.id, root.timeline, root.actor, root.parents, [delta], root.epoch)
  child = replication_batch(timeline, 2u64, replication_version(root.id), 1u64)
  dag.insert_on_timeline(root)
  dag.insert_on_timeline(child)
  dag.begin_epoch
  dag
end

describe "checkpoint and replication" do
  it "round-trips deterministic checkpoints with binary payloads" do
    dag = replication_dag(DeltaDB::HistoryId.random)
    encoded = DeltaDB::Checkpoint::Codec.encode(dag.checkpoint)
    decoded = DeltaDB::Checkpoint::Codec.decode(encoded)

    DeltaDB::Checkpoint::Codec.encode(decoded).should eq encoded
    decoded.history_id.should eq dag.history_id
    decoded.batches.size.should eq 2
    decoded.timelines.size.should eq 1
    decoded.epochs.size.should eq 1
    decoded.batches.first.deltas.first.value.should eq Bytes[0u8, 1u8, 255u8]
    expect_raises(ArgumentError) { DeltaDB::Checkpoint::Codec.decode("not-a-checkpoint") }
  end

  it "publishes and installs checkpoints through explicit phases" do
    dag = replication_dag(DeltaDB::HistoryId.random)
    publisher = DeltaDB::Checkpoint::Publisher.new
    publication = publisher.prepare(dag)
    publication.phase.should eq DeltaDB::Checkpoint::Publication::Phase::Prepared

    publisher.publish(publication.id).phase.should eq DeltaDB::Checkpoint::Publication::Phase::Published
    restored = publisher.install(publication.id)
    restored.timeline_version.should eq dag.timeline_version
    publication.phase.should eq DeltaDB::Checkpoint::Publication::Phase::Installed
    expect_raises(ArgumentError) { publisher.install(publication.id) }
  end

  it "persists replication outbox state through failure and retry" do
    storage = DeltaDB::Storage.in_memory
    dag = replication_dag(DeltaDB::HistoryId.random)
    outbox = DeltaDB::Replication::Outbox.new(storage)
    entry = outbox.append(DeltaDB::Replication::Pack.from(dag, DeltaDB::History::Version.new))

    outbox.size.should eq 1
    outbox.fail(entry.id, "transport failed")
    outbox.pending.should be_empty
    outbox.retry(entry.id)

    recovered = DeltaDB::Replication::Outbox.new(storage)
    recovered.size.should eq 1
    recovered.pending.first.state.should eq DeltaDB::Replication::Outbox::Entry::State::Pending
    recovered.acknowledge(entry.id)
    recovered.size.should eq 0
  end

  it "synchronizes divergent histories and duplicate packs idempotently" do
    history = DeltaDB::HistoryId.random
    local = replication_dag(history)
    remote = DeltaDB::Replication::Peer.new
    storage = DeltaDB::Storage.in_memory
    sync = DeltaDB::Replication::Sync.new(storage, remote)

    sync.push_history(local)
    sync.outbox.size.should eq 0
    remote.history(history).timeline_version.should eq local.timeline_version

    remote_timeline = replication_timeline(2u64)
    remote_root = replication_batch(remote_timeline, 3u64)
    remote.history(history).insert_on_timeline(remote_root)
    sync.pull_history(local)
    local.batches.has_key?(remote_root.id).should be_true
    local.timeline_version.should eq remote.history(history).timeline_version

    pack = remote.pack_for_history(history, DeltaDB::History::Version.new)
    remote.install_pack(pack)
    remote.install_pack(pack)
    remote.packs.size.should eq 2
    sync.connection_state(history).status.should eq DeltaDB::Replication::Connection::Status::Synced
  end

  it "preserves remote reset and fork lineage" do
    history = DeltaDB::HistoryId.random
    local = replication_dag(history)
    remote = DeltaDB::Replication::Peer.new
    sync = DeltaDB::Replication::Sync.new(DeltaDB::Storage.in_memory, remote)
    timeline = replication_timeline(1u64)
    root_id = DeltaDB::DeltaBatchId.new(timeline.uuid, 1u64)
    sync.push_history(local)

    reset = sync.reset_local_timeline(local, timeline, replication_version(root_id))
    reset.generation.should eq 1u32
    local.timeline_parent_id(reset).should eq timeline
    remote.history(history).timeline_parent_id(reset).should eq timeline
    sync.connection_state(history).reset_generation.should eq 1u32

    target = replication_timeline(2u64)
    forked = sync.fork_remote_timeline(local, timeline, target)
    forked.parent.should eq timeline
    remote.history(history).timeline_parent_id(target).should eq timeline
  end

  it "recovers persisted connection state" do
    history = DeltaDB::HistoryId.random
    local = replication_dag(history)
    remote = DeltaDB::Replication::Peer.new
    storage = DeltaDB::Storage.in_memory
    sync = DeltaDB::Replication::Sync.new(storage, remote)
    sync.push_history(local)

    recovered = DeltaDB::Replication::Sync.new(storage, remote).connection_state(history)
    recovered.status.should eq DeltaDB::Replication::Connection::Status::Synced
    recovered.local_version.should eq local.timeline_version
    recovered.remote_version.should eq local.timeline_version
  end

  it "persists checkpoint publication state" do
    storage = DeltaDB::Storage.in_memory
    dag = replication_dag(DeltaDB::HistoryId.random)
    publication = DeltaDB::Checkpoint::Publication.new(UUID.random.to_s, dag.history_id, dag.timeline_version, DeltaDB::Checkpoint::Codec.encode(dag.checkpoint))

    storage.insert_checkpoint_publication(publication)
    storage.transition_checkpoint_publication_phase(publication.id, DeltaDB::Checkpoint::Publication::Phase::Published)
    loaded = storage.checkpoint_publication(publication.id).not_nil!

    loaded.phase.should eq DeltaDB::Checkpoint::Publication::Phase::Published
    loaded.version.should eq dag.timeline_version
    DeltaDB::History::Dag.from_snapshot(DeltaDB::Checkpoint::Codec.decode(loaded.encoded)).timeline_version.should eq dag.timeline_version
    storage.checkpoint_publications.map(&.id).should contain publication.id
  end

  it "rejects corrupted replication packs without losing state" do
    storage = DeltaDB::Storage.in_memory
    dag = replication_dag(DeltaDB::HistoryId.random)
    outbox = DeltaDB::Replication::Outbox.new(storage)
    entry = outbox.append(DeltaDB::Replication::Pack.from(dag, DeltaDB::History::Version.new))

    expect_raises(JSON::ParseException) { DeltaDB::Replication::PackCodec.decode("{}") }
    outbox.retry(entry.id)
    outbox.pending.first.pack.snapshot.history_id.should eq dag.history_id
    outbox.size.should eq 1
  end
end
