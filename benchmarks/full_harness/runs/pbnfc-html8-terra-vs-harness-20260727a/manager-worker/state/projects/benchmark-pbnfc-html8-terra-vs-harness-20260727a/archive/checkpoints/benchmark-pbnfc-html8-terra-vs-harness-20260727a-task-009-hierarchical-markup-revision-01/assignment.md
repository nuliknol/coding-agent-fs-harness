# Harness Continuation Context

Task-Root: 009-hierarchical-markup
Starting-Progress: 33%
Progress-File: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/control/progress/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-009-hierarchical-markup.progress.md
Root-Assignment: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/control/progress/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-009-hierarchical-markup.root-assignment.md
Criteria-Definition: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/control/progress/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-009-hierarchical-markup.root-assignment.md
Target-Criterion: p009.hierarchical-rejection-diagnostics

Preserve all previously verified work. This revision may address only the first unmet criterion shown above. Unrelated failures are known limitations and must not broaden this task.

---

# Harness Continuation Context

Task-Root: 009-hierarchical-markup
Starting-Progress: 33%
Preserve verified criterion: p009.hierarchical-markup-acceptance.
Stress/repetition work remains outside this leaf.

Task-ID: 009-hierarchical-markup-revision-01
Root-Task: 009-hierarchical-markup
Execution-Mode: LEAF_GOAL
Goal-ID: p009.goal.hierarchical-rejection-diagnostics
Target-Criterion: p009.hierarchical-rejection-diagnostics
Goal-Success-Evidence: mismatched or unknown hierarchical markup is rejected by the public CLI with exit status 1 and a single `REJECT` line containing decimal offset, line, column, and nonempty expected fields.
Focused-Validation: Run make test-hierarchical-rejection-core.
Allowed-Scope: src/main.c, src/recognizer.c, tests/hierarchical_rejection_smoke.c, and its Makefile target only.
Baseline-Boundary: p009.hierarchical-markup-acceptance is checkpointed at 33%; public mismatch diagnostics are the next required integration boundary.
Hard-Block-Conditions: None expected; repository-local recognizer, CLI, and focused-test work must be resolved within scope.
