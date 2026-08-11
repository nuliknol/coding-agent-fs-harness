# Worker Leaf Goal

Task-ID: 009-hierarchical-markup-revision-01
Goal-ID: p009.goal.hierarchical-rejection-diagnostics
Target-Criterion: p009.hierarchical-rejection-diagnostics
Goal-Success-Evidence: mismatched or unknown hierarchical markup is rejected by the public CLI with exit status 1 and a single `REJECT` line containing decimal offset, line, column, and nonempty expected fields.
Focused-Validation: Run make test-hierarchical-rejection-core.
Allowed-Scope: src/main.c, src/recognizer.c, tests/hierarchical_rejection_smoke.c, and its Makefile target only.
Baseline-Boundary: p009.hierarchical-markup-acceptance is checkpointed at 33%; public mismatch diagnostics are the next required integration boundary.
Hard-Block-Conditions: None expected; repository-local recognizer, CLI, and focused-test work must be resolved within scope.

Iteration receipts are authoritative in: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/control/goals/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-009-hierarchical-markup-revision-01.iterations.tsv

## Terminal worker outcome

Outcome: COMPLETE
Result: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/results/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-009-hierarchical-markup-revision-01.result.md
Published-At: 2026-07-28T05:46:21Z
