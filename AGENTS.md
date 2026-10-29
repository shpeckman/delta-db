# delta-db agent guide

## Layout

- `src/delta_db.cr`: library entrypoint and version constant.
- `src/delta_db/`: one file per primary type, named after it. Top level holds cross-domain types: errors, causality (`replica_id.cr`, `lamport.cr`, `clock.cr`, `version_vector.cr`), identities (`ids.cr`, `timeline_id.cr`, `delta_batch_id.cr`), `delta.cr`, and the client objects (`buffer.cr`, `map.cr`, `client_operation.cr`, `replica.cr`, `seal_state.cr`, `file_mode.cr`, `file_delta.cr`, `worktree.cr`, `repository.cr`, `fragment_index.cr`, `client.cr`).
- Namespaces mirror directories, and a type nested in a class lives in `<class>/`: `text/` holds `DeltaDB::Text` (rope, buffer, snapshot, anchors, operations, undo, line endings, diff/patch utilities); `history/` holds `DeltaDB::History` (`Version`, `Dag`, `Batch`, `Timeline`, `Epoch`, `Snapshot`, `Record`, `MergeBase`); `checkpoint/` holds `DeltaDB::Checkpoint`; `replication/` holds `DeltaDB::Replication`; `blob/` holds `Blob::Ref` and `Blob::Store`; `map/`, `repository/`, `worktree/`, `fragment_index/`, and `storage/` hold types nested in those classes.
- Add new files to the explicit require list in `src/delta_db.cr`.
- `spec/support/`: spec-only helpers loaded by `spec/spec_helper.cr`; `TestNetwork(T)` simulates duplicate/out-of-order delivery for convergence specs.
- `spec/delta_db/`: unit and differential specs, one `<subject>_spec.cr` per source file or namespace; `text_crdt_spec.cr` covers fragments, anchors, undo, and replica convergence; `history_dag_spec.cr` and `history_storage_spec.cr` cover DAG algorithms, packing, migrations, runs, and checkpoints; `client_models_spec.cr` covers typed deltas, worktrees, fragments, blobs, sealing, and repositories; `replication_spec.cr` covers checkpoint codecs, outbox, sync, and recovery.
- `shard.yml`: Crystal and sqlite3 dependency declarations.

## Commands

```sh
shards install
crystal spec
```

For populated-Delta interoperability coverage:

```sh
DELTA_DB_REFERENCE_DATABASE=/path/to/data.sqlite crystal spec
```

The reference database is opened read-only. Do not use `Storage.open` on it because initialization runs migrations.

## Code standards

- Start every Crystal file with a comment containing its repository-relative path.
- Otherwise avoid comments unless they explain non-obvious reasoning.
- Keep APIs complete and ergonomic; no stubs or placeholders.
- Do not change the `version` field in `shard.yml`.
- Never use `out` as an identifier.
- Match existing Crystal 1.22 idioms and avoid unrelated edits.

Zentry watches this repository and records changes automatically. Do not run manual `git commit`, `git push`, `git reset --hard`, or `git branch -D`. Use zentry commands for undo, release, and backup workflows.
