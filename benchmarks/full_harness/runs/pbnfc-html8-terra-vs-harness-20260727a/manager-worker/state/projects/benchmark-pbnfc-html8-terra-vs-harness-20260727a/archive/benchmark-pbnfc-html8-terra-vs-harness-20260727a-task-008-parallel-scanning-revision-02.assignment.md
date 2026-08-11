# Harness Continuation Context

Task-Root: 008-parallel-scanning
Starting-Progress: 66%
Progress-File: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/control/progress/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-008-parallel-scanning.progress.md
Root-Assignment: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/control/progress/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-008-parallel-scanning.root-assignment.md
Criteria-Definition: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/control/progress/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-008-parallel-scanning.root-assignment.md
Target-Criterion: p008.worker-statistics

Preserve all previously verified work. This revision may address only the first unmet criterion shown above. Unrelated failures are known limitations and must not broaden this task.

---

# Harness Continuation Context

Task-Root: 008-parallel-scanning
Starting-Progress: 66%
Preserve verified criteria: p008.parallel-scanning-workers and p008.scanning-merge-dedup.
Do not broaden into hierarchical grammar integration, rejection diagnostics, README, or final aggregate validation.

Task-ID: 008-parallel-scanning-revision-02
Root-Task: 008-parallel-scanning
Execution-Mode: LEAF_GOAL
Goal-ID: p008.goal.worker-statistics
Target-Criterion: p008.worker-statistics
Goal-Success-Evidence: `bin/pbnfc --stats` emits the required deterministic same-line fields `workers=8`, `active_workers=8`, positive `rounds=`, and eight positive comma-separated task counts for a stress document.
Focused-Validation: Run make test-worker-stats-core.
Allowed-Scope: src/main.c, include/recognizer.h, tests/worker_stats_smoke.c, and its Makefile target only.
Baseline-Boundary: parallel scanning and scan merge/dedup are checkpointed at 66%; the public CLI statistics contract is the only remaining item-008 criterion.
Hard-Block-Conditions: None expected; repository-local CLI, test, and build-target work must be resolved within scope.
