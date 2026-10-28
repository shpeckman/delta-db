# delta-db

Crystal clean-room reconstruction of DeltaDB identity, text, history, and SQLite primitives. The shard remains a partial implementation; checkpointing, replication, remote sync, and full client/worktree models are not complete.

## Setup

```sh
shards install
crystal spec
```

## Identity and versions

`HistoryVersion` is a sorted, deduplicated set of `DeltaBatchId` values. Use `from_id`, `from_ids`, `observe`, `union`, and `contains?` to construct and inspect versions.

Persisted version text is a comma-separated list of `actor_ordinal:timestamp` entries. `encode_version_text` accepts a `Hash(UUID, Int64)` keyed by timeline UUID. `decode_version_text` accepts a `Hash(Int64, TimelineId)` keyed by actor ordinal. Empty text represents an empty version. Malformed entries and unknown actors raise `ArgumentError`.

```crystal
require "delta-db"

first = DeltaDB::DeltaBatchId.new(UUID.random, 1_u64)
version = DeltaDB::HistoryVersion.from_id(first)
version.contains?(first) # => true
```

## Text CRDT buffers

`TextBuffer` applies local edits, exchanges full-offset operations with replicas, resolves timestamped anchors, and generates/applies undo operations. `BufferSnapshot` exposes visible text, deleted text, fragments, insertion metadata, version state, and causal deferral.

```crystal
buffer = DeltaDB::TextBuffer.new(DeltaDB::ReplicaId::LOCAL, DeltaDB::BufferId.new(1_u64), "abc")
operation = buffer.edit([{1...2, "X"}])
buffer.text # => "aXc"

anchor = buffer.anchor_before(2)
buffer.undo
buffer.text # => "abc"
```

Remote operations carry the sender's causal `version`. Operations arriving before their dependencies remain deferred. Duplicate timestamps are applied once. `Network(T)` provides seeded duplicate/out-of-order delivery for convergence testing. `check_invariants` verifies fragment ordering, text lengths, and visible/deleted rope consistency.

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

## Populated Delta differential test

Set `DELTA_DB_REFERENCE_DATABASE` to a genuine populated Delta `data.sqlite`. The differential spec opens it read-only and decodes/re-encodes every row in `history_versions` using that history's actor mappings.

```sh
DELTA_DB_REFERENCE_DATABASE=/path/to/data.sqlite crystal spec
```

Without this variable, the differential spec reports one pending example. A passing unit suite without the fixture is not evidence of real-database interoperability.
