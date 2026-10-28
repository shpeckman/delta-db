# spec/delta_db/client_models_spec.cr
require "../spec_helper"

private def client_delta(history : DeltaDB::HistoryId, timeline : DeltaDB::TimelineId, actor : DeltaDB::ActorUuid, timestamp : DeltaDB::Lamport, operation : DeltaDB::ClientOperation) : DeltaDB::Delta
  DeltaDB::Delta.new(history, timeline, actor, timestamp, Bytes.empty, operation)
end

private def next_timestamp(clock : DeltaDB::Clock) : DeltaDB::Lamport
  clock.tick
end

describe "typed client models" do
  it "stores every map entry kind and filters changes by version" do
    map = DeltaDB::Map.new
    blobs = DeltaDB::BlobStore.new
    blob = blobs.put("blob".to_slice)
    buffer = DeltaDB::ClientBuffer.new(DeltaDB::BufferId.new(1u64), text: "text")
    nested = DeltaDB::Map.new
    worktree = DeltaDB::Worktree.new
    version = DeltaDB::Global.new
    version.observe(DeltaDB::Lamport.new(DeltaDB::ReplicaId::LOCAL, 3u32))

    map.set("register", "value", version)
    map.set_blob("blob", blob, version)
    map.set_buffer("buffer", buffer, version)
    map.set_map("map", nested, version)
    map.set_worktree("worktree", worktree, version)

    map.get("register").should eq "value"
    map.entry("blob").not_nil!.kind.should eq DeltaDB::MapEntryKind::Blob
    map.entry("buffer").not_nil!.kind.should eq DeltaDB::MapEntryKind::Buffer
    map.entry("map").not_nil!.kind.should eq DeltaDB::MapEntryKind::Map
    map.entry("worktree").not_nil!.kind.should eq DeltaDB::MapEntryKind::Worktree
    map.changes(DeltaDB::Global.new).size.should eq 5
    map.changes(version).should be_empty
    map.delete("register")
    map.get("register").should be_nil
  end

  it "edits client buffers and enforces sealing" do
    buffer = DeltaDB::ClientBuffer.new(DeltaDB::BufferId.new(1u64), text: "abc")
    anchor = buffer.create_anchor(2, DeltaDB::Bias::Left)
    buffer.edit_as_actor([{1...2, "X"}])

    buffer.text.should eq "aXc"
    buffer.resolve_anchor(anchor).should eq 2
    buffer.as_rope.to_s.should eq "aXc"
    buffer.fragments.map(&.text).join.should eq "aXbc"
    buffer.seal
    buffer.sealed?.should be_true
    expect_raises(Exception) { buffer.edit_as_actor([{0...0, "Y"}]) }
  end

  it "applies typed deltas through replicas and DAG history" do
    history_id = DeltaDB::HistoryId.random
    timeline = DeltaDB::TimelineId.random
    actor = DeltaDB::ActorUuid.random
    clock = DeltaDB::Clock.new
    replica = DeltaDB::Replica(DeltaDB::Map).new(DeltaDB::Map.new, history_id: history_id)
    buffer = DeltaDB::ClientBuffer.new(DeltaDB::BufferId.new(1u64), text: "abc")
    replica.value.set_buffer("document", buffer)

    first = client_delta(history_id, timeline, actor, next_timestamp(clock), DeltaDB::ClientOperation.register("status", "ready"))
    second = client_delta(history_id, timeline, actor, next_timestamp(clock), DeltaDB::ClientOperation.buffer_edit("document", [1...2], ["X"]))
    replica.apply_history_delta(first)
    replica.apply_history_delta(second)

    replica.value.get("status").should eq "ready"
    replica.value.entry("document").not_nil!.buffer.not_nil!.text.should eq "aXc"
    replica.history.batches.size.should eq 2
    replica.outgoing_history_deltas.should eq [first, second]
    replica.drain_confirmed_outgoing.size.should eq 2
    replica.outgoing_history_deltas.should be_empty

    replica.apply_history_delta(client_delta(history_id, timeline, actor, next_timestamp(clock), DeltaDB::ClientOperation.seal))
    replica.sealed?.should be_true
    expect_raises(Exception) do
      replica.apply_history_delta(client_delta(history_id, timeline, actor, next_timestamp(clock), DeltaDB::ClientOperation.register("blocked", "yes")))
    end
  end

  it "applies worktree deltas and restores snapshots with blobs" do
    worktree = DeltaDB::Worktree.new
    worktree.create("src/a.txt", "hello")
    worktree.apply(DeltaDB::SetLineEndingsDelta.new("src/a.txt", DeltaDB::LineEnding::Crlf))
    worktree.apply(DeltaDB::EditFileDelta.new("src/a.txt", "hello world"))
    worktree.apply(DeltaDB::CreateDirDelta.new("src/lib"))
    worktree.apply(DeltaDB::CreateSymlinkDelta.new("src/link", "a.txt"))
    worktree.apply(DeltaDB::RenameDelta.new("src/a.txt", "src/b.txt"))
    snapshot = worktree.snapshot

    worktree.read("src/b.txt").should eq "hello world"
    worktree.files["src/link"].symlink_target.should eq "a.txt"
    worktree.blob("src/b.txt").not_nil!.resolve(worktree.blob_store).should eq "hello world".to_slice

    restored = DeltaDB::Worktree.new
    restored.restore(snapshot)
    restored.read("src/b.txt").should eq "hello world"
    restored.snapshot.version.should eq snapshot.version

    worktree.apply(DeltaDB::DeleteDelta.new("src/b.txt"))
    worktree.read("src/b.txt").should be_nil
    worktree.seal
    expect_raises(Exception) { worktree.apply(DeltaDB::CreateDirDelta.new("blocked")) }
  end

  it "edits worktree text and builds fragment indexes" do
    worktree = DeltaDB::Worktree.new
    worktree.create("a.txt", "hello world")
    text = DeltaDB::WorktreeText.new(worktree)

    text.edit("a.txt", [6...11], ["there"])
    text.read("a.txt").should eq "hello there"
    text.save("a.txt")
    worktree.read("a.txt").should eq "hello there"
    index = text.fragment_index("a.txt")
    index.records.size.should be > 0
    index.records.keys.map { |id| index.resolve(id) }.join.should eq "hello there"
  end

  it "applies sorted fragment edit plans and rejects overlaps" do
    index = DeltaDB::FragmentIndex.new
    record = index.insert("hello world")
    plan = DeltaDB::EditPlan.new(record.id, [
      DeltaDB::ContentSplice.new(0u32...0u32, ">"),
      DeltaDB::ContentSplice.new(6u32...11u32, "there"),
    ])

    edits = index.apply(plan)
    edits.size.should eq 2
    index.resolve(record.id).should eq ">hello there"
    overlapping = DeltaDB::EditPlan.new(record.id, [
      DeltaDB::ContentSplice.new(0u32...3u32, "a"),
      DeltaDB::ContentSplice.new(2u32...4u32, "b"),
    ])
    expect_raises(ArgumentError) { index.apply(overlapping) }
  end

  it "deduplicates content-addressed blobs and restores snapshots" do
    store = DeltaDB::BlobStore.new
    first = store.put("same".to_slice)
    second = store.put("same".to_slice)

    first.digest.should eq second.digest
    first.resolve(store).should eq "same".to_slice
    snapshot = store.snapshot
    restored = DeltaDB::BlobStore.new
    restored.restore(snapshot)
    first.resolve(restored).should eq "same".to_slice
  end

  it "synchronizes repositories and restores full snapshots" do
    client = DeltaDB::Client.new
    repository = client.create_repository
    history_id = repository.history.history_id
    timeline = DeltaDB::TimelineId.random
    actor = DeltaDB::ActorUuid.random
    clock = DeltaDB::Clock.new
    blob = repository.blob_store.put("blob".to_slice)
    operation = DeltaDB::ClientOperation.blob("payload", blob)
    delta = client_delta(history_id, timeline, actor, next_timestamp(clock), operation)

    client.apply_history_delta(repository, delta)
    client.outgoing_history_delta_count.should eq 1
    client.outgoing_history_queue_is_empty?.should be_false
    snapshot = repository.snapshot
    restored = DeltaDB::Repository.from_snapshot(snapshot)
    restored.map.entry("payload").not_nil!.blob.not_nil!.resolve(restored.blob_store).should eq "blob".to_slice
    restored.history.batches.size.should eq 1
    client.drain_confirmed_outgoing.size.should eq 1
    client.outgoing_history_queue_is_empty?.should be_true

    storage = DeltaDB::Storage.in_memory
    client.save(storage)
    storage.load_dag(history_id).batches.size.should eq 1

    remote = DeltaDB::RemoteRepositoryId.random
    shared = client.open_shared_repository(remote)
    client.open_shared_repository(remote).should eq shared
  end
end
