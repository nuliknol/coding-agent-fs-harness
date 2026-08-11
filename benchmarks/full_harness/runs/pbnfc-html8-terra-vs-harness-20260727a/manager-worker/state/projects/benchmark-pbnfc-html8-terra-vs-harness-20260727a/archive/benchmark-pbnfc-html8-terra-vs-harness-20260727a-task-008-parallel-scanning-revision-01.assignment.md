# Harness Continuation Context

Task-Root: 008-parallel-scanning
Starting-Progress: 33%
Progress-File: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/control/progress/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-008-parallel-scanning.progress.md
Root-Assignment: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/control/progress/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-008-parallel-scanning.root-assignment.md
Criteria-Definition: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/control/progress/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-008-parallel-scanning.root-assignment.md
Target-Criterion: p008.scanning-merge-dedup

Preserve all previously verified work. This revision may address only the first unmet criterion shown above. Unrelated failures are known limitations and must not broaden this task.

---

# Harness Continuation Context

Task-Root: 008-parallel-scanning
Starting-Progress: 33%
Preserve verified criterion: p008.parallel-scanning-workers.
Do not alter CLI statistics formatting, hierarchical grammar behavior, or final regression scope.

Task-ID: 008-parallel-scanning-revision-01
Root-Task: 008-parallel-scanning
Execution-Mode: LEAF_GOAL
Goal-ID: p008.goal.scanning-merge-dedup
Target-Criterion: p008.scanning-merge-dedup
Goal-Success-Evidence: scan candidates from all worker-private vectors are deterministically ordered and deduplicated before insertion into the next chart position, with a duplicate-producing focused smoke confirming repeatable recognition.
Focused-Validation: Run make test-parallel-scanning-core.
Allowed-Scope: src/recognizer.c, tests/parallel_scanning_smoke.c, and its Makefile target only.
Baseline-Boundary: p008.parallel-scanning-workers is checkpointed at 33%; generic closure merging is accepted from item 007 but scan-specific merge/dedup evidence remains required.
Hard-Block-Conditions: None expected; repository-local recognizer or focused-test work must be resolved within scope.
