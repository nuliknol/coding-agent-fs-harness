# Worker Leaf Goal

Task-ID: 008-parallel-scanning-revision-02
Goal-ID: p008.goal.worker-statistics
Target-Criterion: p008.worker-statistics
Goal-Success-Evidence: `bin/pbnfc --stats` emits the required deterministic same-line fields `workers=8`, `active_workers=8`, positive `rounds=`, and eight positive comma-separated task counts for a stress document.
Focused-Validation: Run make test-worker-stats-core.
Allowed-Scope: src/main.c, include/recognizer.h, tests/worker_stats_smoke.c, and its Makefile target only.
Baseline-Boundary: parallel scanning and scan merge/dedup are checkpointed at 66%; the public CLI statistics contract is the only remaining item-008 criterion.
Hard-Block-Conditions: None expected; repository-local CLI, test, and build-target work must be resolved within scope.

Iteration receipts are authoritative in: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/control/goals/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-008-parallel-scanning-revision-02.iterations.tsv

## Terminal worker outcome

Outcome: COMPLETE
Result: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/results/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-008-parallel-scanning-revision-02.result.md
Published-At: 2026-07-28T05:39:41Z
