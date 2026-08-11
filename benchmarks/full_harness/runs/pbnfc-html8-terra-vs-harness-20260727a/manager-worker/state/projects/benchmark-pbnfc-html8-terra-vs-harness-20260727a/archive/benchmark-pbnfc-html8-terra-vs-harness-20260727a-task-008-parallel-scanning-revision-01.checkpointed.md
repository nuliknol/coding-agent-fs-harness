# Checkpointed Task Increment

Project: benchmark-pbnfc-html8-terra-vs-harness-20260727a

Task-ID: 008-parallel-scanning-revision-01

Task-Root: 008-parallel-scanning

Environment-File: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/harness.env

Checkpointed-At: 2026-07-28T05:35:24Z

Artifact-Directory: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/archive/checkpoints/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-008-parallel-scanning-revision-01

## Review notes

# Manager Review Record

Task-ID: 008-parallel-scanning-revision-01
Decision: CHECKPOINT
Progress-Percent: 66%
Improvement-Percent: 33%
Verified-Criterion: p008.scanning-merge-dedup
Checkpoint-Path: src/recognizer.c
Checkpoint-Path: tests/parallel_scanning_smoke.c

## Specification comparison
The coordinator now applies one stable chart-item identity predicate to compact sorted candidates before touching the next chart position, including candidates produced by scan generations.

## Increment verification
- [PASS] p008.scanning-merge-dedup — `merge_parallel_candidates` orders candidates then compacts `pbnfc_chart_item_equal` duplicates before coordinator-only insertion; the focused grammar produces duplicate closure candidates followed by a parallel scan.

## Validation executed
- [PASS] `make -B test-parallel-scanning-core` — forced strict C11/pthread rebuild and duplicate-producing, repeatability-focused scan smoke completed with exit status 0.

## Scope and regression review
Reviewed only the allowed recognizer merge boundary and scan smoke. Both parallel recognition runs produced equal rounds, total work, and per-worker scan work; CLI statistics formatting remains untouched for the final root criterion.

## Remaining root criteria
- p008.worker-statistics

## Conclusion
This increment is correct and independently verified, while the root remains incomplete. Checkpoint.

