# spec/delta_db/client_models_spec.cr
require "file_utils"
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
    blobs = DeltaDB::Blob::Store.new
    blob = blobs.put("blob".to_slice)
    buffer = DeltaDB::Buffer.new(DeltaDB::Text::BufferId.new(1u64), text: "text")
    nested = DeltaDB::Map.new
    worktree = DeltaDB::Worktree.new
    version = DeltaDB::VersionVector.new
    version.observe(DeltaDB::Lamport.new(DeltaDB::ReplicaId::LOCAL, 3u32))

    map.set("register", "value", version)
    map.set_blob("blob", blob, version)
    map.set_buffer("buffer", buffer, version)
    map.set_map("map", nested, version)
    map.set_worktree("worktree", worktree, version)

    map.get("register").should eq "value"
    map.entry("blob").not_nil!.kind.should eq DeltaDB::Map::Entry::Kind::Blob
    map.entry("buffer").not_nil!.kind.should eq DeltaDB::Map::Entry::Kind::Buffer
    map.entry("map").not_nil!.kind.should eq DeltaDB::Map::Entry::Kind::Map
    map.entry("worktree").not_nil!.kind.should eq DeltaDB::Map::Entry::Kind::Worktree
    map.changes(DeltaDB::VersionVector.new).size.should eq 5
    map.changes(version).should be_empty
    map.delete("register")
    map.get("register").should be_nil
  end

  it "edits client buffers and enforces sealing" do
    buffer = DeltaDB::Buffer.new(DeltaDB::Text::BufferId.new(1u64), text: "abc")
    anchor = buffer.create_anchor(2, DeltaDB::Text::Bias::Left)
    buffer.edit_as_actor([{1...2, "X"}])

    buffer.text.should eq "aXc"
    buffer.resolve_anchor(anchor).should eq 2
    buffer.to_rope.to_s.should eq "aXc"
    buffer.fragments.map(&.text).join.should eq "aXbc"
    buffer.seal
    buffer.sealed?.should be_true
    expect_raises(DeltaDB::SealedError) { buffer.edit_as_actor([{0...0, "Y"}]) }
  end

  it "applies typed deltas through replicas and DAG history" do
    history_id = DeltaDB::HistoryId.random
    timeline = DeltaDB::TimelineId.random
    actor = DeltaDB::ActorUuid.random
    clock = DeltaDB::Clock.new
    replica = DeltaDB::Replica(DeltaDB::Map).new(DeltaDB::Map.new, history_id: history_id)
    buffer = DeltaDB::Buffer.new(DeltaDB::Text::BufferId.new(1u64), text: "abc")
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
    expect_raises(DeltaDB::SealedError) do
      replica.apply_history_delta(client_delta(history_id, timeline, actor, next_timestamp(clock), DeltaDB::ClientOperation.register("blocked", "yes")))
    end
  end

  it "applies worktree deltas and restores snapshots with blobs" do
    worktree = DeltaDB::Worktree.new
    worktree.create("src/a.txt", "hello")
    worktree.apply(DeltaDB::FileDelta::SetLineEndings.new("src/a.txt", DeltaDB::Text::LineEnding::Crlf))
    worktree.apply(DeltaDB::FileDelta::Edit.new("src/a.txt", "hello world"))
    worktree.apply(DeltaDB::FileDelta::CreateDir.new("src/lib"))
    worktree.apply(DeltaDB::FileDelta::CreateSymlink.new("src/link", "a.txt"))
    worktree.apply(DeltaDB::FileDelta::Rename.new("src/a.txt", "src/b.txt"))
    snapshot = worktree.snapshot

    worktree.read("src/b.txt").should eq "hello world"
    worktree.files["src/link"].symlink_target.should eq "a.txt"
    worktree.blob("src/b.txt").not_nil!.resolve(worktree.blob_store).should eq "hello world".to_slice

    restored = DeltaDB::Worktree.new
    restored.restore(snapshot)
    restored.read("src/b.txt").should eq "hello world"
    restored.snapshot.version.should eq snapshot.version

    snapshot_size = snapshot.version.size
    worktree.apply(DeltaDB::FileDelta::Delete.new("src/b.txt"))
    worktree.read("src/b.txt").should be_nil
    snapshot.version.size.should eq snapshot_size
    worktree.snapshot.version.size.should eq snapshot_size + 1
    worktree.seal
    expect_raises(DeltaDB::SealedError) { worktree.apply(DeltaDB::FileDelta::CreateDir.new("blocked")) }
  end

  it "edits worktree text and builds fragment indexes" do
    worktree = DeltaDB::Worktree.new
    worktree.create("a.txt", "hello world")
    text = DeltaDB::Worktree::Editor.new(worktree)

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
    plan = DeltaDB::FragmentIndex::EditPlan.new(record.id, [
      DeltaDB::FragmentIndex::Splice.new(0u32...0u32, ">"),
      DeltaDB::FragmentIndex::Splice.new(6u32...11u32, "there"),
    ])

    edits = index.apply(plan)
    edits.size.should eq 2
    index.resolve(record.id).should eq ">hello there"
    overlapping = DeltaDB::FragmentIndex::EditPlan.new(record.id, [
      DeltaDB::FragmentIndex::Splice.new(0u32...3u32, "a"),
      DeltaDB::FragmentIndex::Splice.new(2u32...4u32, "b"),
    ])
    expect_raises(ArgumentError) { index.apply(overlapping) }
  end

  it "deduplicates content-addressed blobs and restores snapshots" do
    store = DeltaDB::Blob::Store.new
    first = store.put("same".to_slice)
    second = store.put("same".to_slice)

    first.digest.should eq second.digest
    first.resolve(store).should eq "same".to_slice
    snapshot = store.snapshot
    restored = DeltaDB::Blob::Store.new
    restored.restore(snapshot)
    first.resolve(restored).should eq "same".to_slice
  end

  it "persists disk blobs and reads them through read-only mappings" do
    root = File.tempname("delta-db-blobs")
    begin
      store = DeltaDB::Blob::Store.open(root)
      ref = store.put("mapped".to_slice)
      empty = store.put(Bytes.empty)
      store.put("mapped".to_slice).digest.should eq ref.digest

      ref.read(store) { |bytes| bytes.read_only?.should be_true; String.new(bytes) }.should eq "mapped"
      empty.resolve(store).should eq Bytes.empty
      store.get(ref).read_only?.should be_false

      reopened = DeltaDB::Blob::Store.open(root)
      reopened.contains?(ref).should be_true
      ref.resolve(reopened).should eq "mapped".to_slice
      reopened.snapshot.keys.sort.should eq [ref.digest, empty.digest].sort

      extra = DeltaDB::Blob::Store.new.put("extra".to_slice)
      reopened.restore({extra.digest => "extra".to_slice})
      reopened.contains?(ref).should be_false
      extra.resolve(reopened).should eq "extra".to_slice
      expect_raises(DeltaDB::MissingBlobError) { ref.resolve(reopened) }
      expect_raises(DeltaDB::MissingBlobError) { DeltaDB::Blob::Ref.new(ref.digest, 6u64, false).read(store) { } }
    ensure
      FileUtils.rm_rf(root)
    end
  end

  it "backs repositories with disk blob stores" do
    root = File.tempname("delta-db-blobs")
    begin
      client = DeltaDB::Client.new
      repository = client.create_repository(blob_store: DeltaDB::Blob::Store.open(root))
      blob = repository.blob_store.put("blob".to_slice)
      restored = DeltaDB::Repository.from_snapshot(repository.snapshot, DeltaDB::Blob::Store.open(root))
      blob.resolve(restored.blob_store).should eq "blob".to_slice
      restored.blob_store.backend.should be_a(DeltaDB::Blob::Store::Disk)
    ensure
      FileUtils.rm_rf(root)
    end
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
