# TODO - Remaining Layer B

1. CRDT client (the biggest remaining piece)
  - [ ] client.rs, client/map.rs, client/repository.rs, client/history_wide_connection_state.rs
  - [ ] The Replica/Map — the concurrent-editing document replica, the CRDT map that resolves concurrent inserts/deletes across replicas. I ported the buffer snapshot + patch + operation queue, but not the Replica that drives them.

2. [ ] History engine (DAG + checkpoints)
  - [ ] history.rs, history/dag.rs, history/delta_run.rs, history_records.rs, history_checkpoint.rs, merge_base_resolver.rs
  - [ ] The versioned history DAG (ancestry, delta runs, checkpoint building/verification, merge-base resolution). I ported only the Storage schema + append_delta (monotonic version assign); the actual DAG/topology logic is untouched.

3. [ ] Storage backend remainder
  - [ ] storage/backend.rs (DifferenceWalk, HistoryInterning, HistoryAncestryReader), storage/delta_runs.rs, run_headers.rs, registry.rs, state.rs, attribute.rs, worktree_report.rs
  - [ ] I ported the core tables (histories, history_delta_values, history_versions, history_actors); not the difference-walk/interning logic, run storage, registry, state, or the attribute node-graph.

4. [ ] Replication / remote sync
  - [ ] replicate.rs, remote.rs, remote_sync_signal.rs, plus the cloud tables history_replication_*, history_checkpoint_*, history_blobs
  - [ ] The multi-machine sync protocol (outbox, packs, delta ranges, checkpoint archives). Only the Network test-harness was ported.

5. [ ] Fragment index remainder
  - [ ] fragment_index/alias_span.rs, content_splice.rs, edit_plan.rs
  - [ ] I ported Fragment + BufferSnapshot, but not the FragmentIndex edit-planning pipeline (the alias/span/content-splice machinery for concurrent edits).

6. [ ] Worktree / file-tree
  - [ ] file_tree.rs, file_tree_state.rs, disk_worktree_fs.rs, worktree_text.rs, repository_store.rs
  - [ ] Delta's filesystem worktree abstraction (inode/file-tree state, disk-backed worktree FS). Entirely untouched.

7. [ ] Supporting
  - [ ] git_attributes.rs, file_read_diagnostics.rs, subscription.rs, gpui_ext.rs
