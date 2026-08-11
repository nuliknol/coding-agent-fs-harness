# Root Task Progress

Project: benchmark-pbnfc-html8-terra-vs-harness-20260727a
Task-Root: 008-parallel-scanning
Progress-Percent: 100%
Improvement-Percent: 34%
Last-Reviewed-Task: 008-parallel-scanning-revision-02
Last-Decision: ACCEPT
Updated-At: 2026-07-28T05:40:24Z

## Evidence checkpoint

# Manager Review Record

Task-ID: 008-parallel-scanning-revision-02
Decision: ACCEPT
Progress-Percent: 100%
Verified-Criterion: p008.worker-statistics

## Specification comparison
The public recognizer CLI now executes the persistent parallel pool and, when requested, appends deterministic worker statistics on the successful ACCEPT line in the required field order.

## Acceptance-criteria verification
- [PASS] p008.parallel-scanning-workers — prior checkpoint verifies scan-position range partitioning and private candidates across all eight workers.
- [PASS] p008.scanning-merge-dedup — prior checkpoint verifies deterministic identity-based compaction before scan-candidate insertion.
- [PASS] p008.worker-statistics — `print_stats` emits workers, active workers, rounds, and exactly eight comma-separated task counts on the ACCEPT line.

## Feature verification
- [PASS] public `--stats` contract — the end-to-end smoke invokes `bin/pbnfc --grammar … --input … --stats`, parses the whole output line, and confirms workers=8, active_workers=8, positive rounds, and positive counts for every worker.

## Validation executed
- [PASS] `make -B test-worker-stats-core` — forced strict C11/pthread rebuild, CLI binary build, and focused public-interface smoke completed with exit status 0.

## Scope and regression review
Reviewed `src/main.c`, the dedicated smoke, and its Makefile target. The change confines output to the documented optional `--stats` suffix while retaining ordinary ACCEPT output and all previously accepted scan/merge behavior.

## Conclusion
All required behavior was independently verified. Accept.

