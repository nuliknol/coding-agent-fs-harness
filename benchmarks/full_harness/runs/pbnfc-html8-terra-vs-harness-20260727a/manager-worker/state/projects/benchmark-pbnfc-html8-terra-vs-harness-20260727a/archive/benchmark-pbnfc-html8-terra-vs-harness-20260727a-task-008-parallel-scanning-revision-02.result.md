# Task Result

Task-ID: 008-parallel-scanning-revision-02
Status: COMPLETED
Goal-ID: p008.goal.worker-statistics
Goal-Outcome: COMPLETE

## Summary

Completed the remaining public CLI worker-statistics criterion at the 66% checkpoint. The CLI now performs the complete grammar-file and input-file recognition path and emits deterministic statistics on the same ACCEPT line.

## Modified files

- `src/main.c`
- `Makefile`
- `tests/worker_stats_smoke.c`

## Implemented behavior

- Loads and parses the requested grammar, validates it, lexes the markup input, and recognizes through the existing persistent parallel worker pool.
- `--stats` appends `workers=`, `active_workers=`, positive `rounds=`, and all eight comma-separated total task counts on the ACCEPT line.
- Preserves existing command-line, grammar, markup, and rejection diagnostics and exit statuses.
- Adds `test-worker-stats-core`, whose smoke invokes the public `bin/pbnfc --stats` interface and verifies all eight workers report positive work.

## Validation performed

- `make test-worker-stats-core` — PASS; strict C11/pthread compilation succeeded and the end-to-end CLI statistics smoke exited 0.
- Workspace fingerprint after implementation: `sha256:545cddd842a16b3350d6a4f8300e4f869bd971996e881582b1ee9beb0c7c55fb`.
- Previously checkpointed parallel scanning and deterministic merge/dedup code was not modified.

## Deviations from assignment

None.

## Remaining concerns

None for `p008.worker-statistics`. The manager-owned final aggregate checks were not run in this bounded worker validation.

## Worker assessment

The leaf success evidence passes: the public CLI emits the required same-line fields with eight workers, eight active workers, positive rounds, and eight positive task counts for the stress fixture. The leaf goal is complete.
