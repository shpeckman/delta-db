# delta-db agent guide

## Layout

- `src/delta_db.cr`: library entrypoint and version constant.
- `src/delta_db/`: identity, text, history, client, and storage modules; `history_engine.cr` contains the DAG and `storage_history.cr` its SQLite persistence.
- `spec/delta_db/`: unit and differential specs; `text_crdt_spec.cr` covers fragments, anchors, undo, and replica convergence; `history_dag_spec.cr` and `history_storage_spec.cr` cover DAG algorithms, packing, migrations, runs, and checkpoints.
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
