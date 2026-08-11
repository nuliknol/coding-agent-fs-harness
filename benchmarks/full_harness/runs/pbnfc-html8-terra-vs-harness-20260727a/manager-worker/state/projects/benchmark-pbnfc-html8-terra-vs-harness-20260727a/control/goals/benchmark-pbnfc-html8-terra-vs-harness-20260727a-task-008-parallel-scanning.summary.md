# Worker Leaf Goal

Task-ID: 008-parallel-scanning
Goal-ID: p008.goal.parallel-scanning-workers
Target-Criterion: p008.parallel-scanning-workers
Goal-Success-Evidence: terminal-matching chart items for a scan position are partitioned across all eight persistent workers, produce next-position candidates in private vectors, and a focused scanning smoke confirms all workers performed work.
Focused-Validation: Run make test-parallel-scanning-core.
Allowed-Scope: src/recognizer.c, include/recognizer.h, tests/parallel_scanning_smoke.c, and the corresponding Makefile target only.
Baseline-Boundary: item 007 is accepted: closure prediction/completion and coordinator merge are deterministic; scanner distribution, scan-specific proof, and stats CLI output are not yet accepted for item 008.
Hard-Block-Conditions: None expected; repository-local recognizer, test, or build-target work must be addressed within scope.

Iteration receipts are authoritative in: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/control/goals/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-008-parallel-scanning.iterations.tsv

## Terminal worker outcome

Outcome: COMPLETE
Result: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/results/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-008-parallel-scanning.result.md
Published-At: 2026-07-28T05:31:09Z
