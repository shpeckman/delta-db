# delta-db

Crystal clean-room reconstruction of DeltaDB identity, text, history, and SQLite primitives. The shard remains a partial implementation; checkpointing, replication, remote sync, and full client/worktree models are not complete.

## Setup

```sh
shards install
crystal spec
```

## Identity and versions

`History::Version` is a sorted, deduplicated set of `DeltaBatchId` values. Versions are immutable: `from_id`, `from_ids`, and `union` (with a `DeltaBatchId` or another `History::Version`) return new values; `contains?`, `size`, and `empty?` inspect them.

Persisted version text is a comma-separated list of `actor_ordinal:timestamp` entries. `encode_version_text` accepts a `Hash(UUID, Int64)` keyed by timeline UUID. `decode_version_text` accepts a `Hash(Int64, TimelineId)` keyed by actor ordinal. Empty text represents an empty version. Malformed entries and unknown actors raise `ArgumentError`.

```crystal
require "delta-db"

first = DeltaDB::DeltaBatchId.new(UUID.random, 1_u64)
version = DeltaDB::History::Version.from_id(first)
version.contains?(first) # => true
```

## History DAG and checkpoint storage

`History::Dag` stores batches with parent versions and supports timeline insertion, reset, fork, lineage, epochs, ancestry, reachability, common ancestors, dominators, and merge-base resolution.

```crystal
dag = DeltaDB::History::Dag.new(DeltaDB::HistoryId.random)
timeline = DeltaDB::TimelineId.random
actor = DeltaDB::ActorUuid.random
root = DeltaDB::History::Batch.new(DeltaDB::DeltaBatchId.new(timeline.uuid, 1_u64), timeline, actor)
dag.insert_on_timeline(root)
forked = dag.fork_timeline(timeline, DeltaDB::TimelineId.random)
```

`History::Dag#checkpoint` returns a `History::Snapshot` containing batches, timelines, epochs, and counters. `History::Dag.from_snapshot` restores it with dependency ordering. `History::MergeBase.resolve(dag, a, b)` returns the maximal shared ancestor or `nil` when no shared batch exists.

`Storage#save_dag`, `#load_dag`, and `#install_checkpoint` persist DAG state transactionally. `#checkpoint` reads a snapshot, while `#record_checkpoint` and `#checkpoint_version` persist/read a boundary. `pack_deltas` stores multiple payloads in one pack and `delta_value` transparently reads inline, overflow, or packed data. `append_run` and `load_runs` persist run headers and ordered segments. New databases use `Storage::CURRENT_SCHEMA_VERSION`; newer unsupported schemas are rejected.

## Client models and repositories

`Map` stores typed register, blob, buffer, nested-map, and worktree entries. `Buffer` wraps the text CRDT engine with anchors, editing, snapshots, and sealing. `ClientOperation` describes typed map/buffer/worktree changes, and `DeltaApplication` applies them. `Replica(T)` applies deltas into a `History::Dag`, tracks outgoing batches, and enforces sealing.

`Blob::Store` content-addresses payloads with SHA-256. `Worktree` applies file deltas, maintains text and blobs, and restores `Worktree::Snapshot` values. `Worktree::Editor` edits files through client buffers and builds `FragmentIndex` values. `FragmentIndex#apply` executes sorted, non-overlapping `FragmentIndex::EditPlan` splices.

`Repository` combines a typed map, DAG replica, and blob store. `Repository::Snapshot` preserves all three. `Repository::Store` manages local/shared repositories, while `Client` applies local/remote batches and drains confirmed outgoing deltas.

```crystal
client = DeltaDB::Client.new
repository = client.create_repository
operation = DeltaDB::ClientOperation.register("status", "ready")
delta = DeltaDB::Delta.new(repository.history.history_id, DeltaDB::TimelineId.random, DeltaDB::ActorUuid.random, DeltaDB::Lamport.new(DeltaDB::ReplicaId::LOCAL), Bytes.empty, operation)
client.apply_history_delta(repository, delta)
repository.map.get("status") # => "ready"
```

## Text CRDT buffers

`Text::Buffer` applies local edits, exchanges full-offset operations with replicas, resolves timestamped anchors, and generates/applies undo operations. `Text::Snapshot` exposes visible text, deleted text, fragments, insertion metadata, version state, and causal deferral.

```crystal
buffer = DeltaDB::Text::Buffer.new(DeltaDB::ReplicaId::LOCAL, DeltaDB::Text::BufferId.new(1_u64), "abc")
operation = buffer.edit([{1...2, "X"}])
buffer.text # => "aXc"

anchor = buffer.anchor_before(2)
buffer.undo
buffer.text # => "abc"
```

Remote operations carry the sender's causal `version`. Operations arriving before their dependencies remain deferred. Duplicate timestamps are applied once. `Network(T)` provides seeded duplicate/out-of-order delivery for convergence testing. `check_invariants` raises `InvariantError` unless it verifies fragment ordering, text lengths, and visible/deleted rope consistency.

## SQLite storage

`Storage.in_memory` creates an isolated database. `Storage.open(path)` opens a file-backed database. `insert_delta` stores a delta and registers its actor. `append_delta` additionally registers the timeline, writes a version, and advances only that timeline's head.

Batch IDs use the delta's Lamport timestamp. Version keys remain storage-local monotonic integers and are distinct from batch timestamps.

```crystal
storage = DeltaDB::Storage.in_memory
history = DeltaDB::HistoryId.random
timeline = DeltaDB::TimelineId.random
clock = DeltaDB::Clock.new
actor = DeltaDB::ActorUuid.random
delta = DeltaDB::Delta.new(history, timeline, actor, clock.tick, "value".to_slice)
version = storage.append_delta(delta)
```

## Checkpoints and replication

`Checkpoint::Codec` encodes `History::Snapshot` in a versioned JSON envelope with Base64 delta payloads. `Checkpoint::Publisher` manages prepared, published, installed, and failed phases. `Replication::Pack.from` creates sealed checkpoint packs and `Replication::PackCodec` round-trips them. `Replication::Outbox` persists pending, failed, and acknowledged packs with retry support.

`Replication::Sync` pushes and pulls checkpoints through `Replication::Peer`, an in-memory remote transport used for deterministic protocol and recovery tests. It supports divergent-history merge, timeline reset/fork, duplicate-pack suppression, and persisted `Replication::Connection`. It is not an implementation of Delta's production network service.

```crystal
remote = DeltaDB::Replication::Peer.new
storage = DeltaDB::Storage.in_memory
sync = DeltaDB::Replication::Sync.new(storage, remote)
sync.push_history(dag)
sync.pull_history(dag)
state = sync.connection_state(dag.history_id)
```

Checkpoint publication, outbox, and connection state use schema version 3. `checkpoint_publication(s)`, `replication_outbox_entries`, and `load_history_connection_state` recover durable state.

## Errors

Library errors inherit from `DeltaDB::Error`. `NotFoundError` reports missing timelines, paths, buffers, fragments, repositories, and checkpoint publications. `SealedError` rejects mutation of sealed buffers, maps, worktrees, and replicas. `MissingBlobError` reports absent or unavailable blob content. `InvariantError` reports failed `check_invariants`. Malformed input raises `ArgumentError`.

Lengths follow Crystal conventions: `bytesize` counts bytes (`Text::Rope::Chunk`, `Text::Rope`, `Text::Snapshot`, `Text::Buffer`, `Buffer`, `Text::Fragment`, `Text::Summary`) and `size` counts elements.

## Populated Delta differential test

Set `DELTA_DB_REFERENCE_DATABASE` to a genuine populated Delta `data.sqlite`. The differential spec opens it read-only and decodes/re-encodes every row in `history_versions` using that history's actor mappings.

```sh
DELTA_DB_REFERENCE_DATABASE=/path/to/data.sqlite crystal spec
```

Without this variable, the differential spec reports one pending example. A passing unit suite without the fixture is not evidence of real-database interoperability.
