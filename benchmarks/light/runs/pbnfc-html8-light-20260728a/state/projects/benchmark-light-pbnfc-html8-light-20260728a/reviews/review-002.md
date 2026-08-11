DECISION: REVISE

1. `ADD-004` — Closure rounds reprocess the whole chart instead of the required unprocessed snapshot range.

   - `Specification:` “For each chart position and fixed-point closure wave: The coordinator snapshots the current unprocessed item range and partitions it across all eight workers.”
   - `Evidence:` In `recognize()` at [src/recognizer.c:280](/var/home/mf/coding-agent-fs-harness/benchmark/light/runs/pbnfc-html8-light-20260728a/repository/src/recognizer.c:280), `processed` is maintained but never supplied to the pool. Each closure call at [src/recognizer.c:290](/var/home/mf/coding-agent-fs-harness/benchmark/light/runs/pbnfc-html8-light-20260728a/repository/src/recognizer.c:290) dispatches `snapshot`, causing `closure_task()` to revisit indices `0..snapshot-1` every wave rather than only `processed..snapshot-1`.
   - `Required correction:` Dispatch precisely the newly appended interval for each closure wave, while retaining the existing deterministic candidate merge/deduplication behavior. Derive worker task statistics from actual nonempty assigned work rather than copying the global pool generation to every worker.
   - `Verification:` Run an epsilon/right-recursive grammar with `--stats` under an instrumented or focused regression check showing each chart item is processed once per closure wave, and run the supplied stress document confirming all eight workers have positive actual task counts.

Build and supplied checks currently pass: `make clean all`, `make test`, and `../grader.sh "$PWD"` (12/12).