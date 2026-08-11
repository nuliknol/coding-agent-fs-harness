# Harness Continuation Context

Task-Root: 009-hierarchical-markup
Starting-Progress: 66%
Progress-File: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/control/progress/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-009-hierarchical-markup.progress.md
Root-Assignment: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/control/progress/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-009-hierarchical-markup.root-assignment.md
Criteria-Definition: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/control/progress/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-009-hierarchical-markup.root-assignment.md
Target-Criterion: p009.hierarchical-stress-repeatability

Preserve all previously verified work. This revision may address only the first unmet criterion shown above. Unrelated failures are known limitations and must not broaden this task.

---

# Harness Continuation Context

Task-Root: 009-hierarchical-markup
Starting-Progress: 66%
Preserve verified criteria: p009.hierarchical-markup-acceptance and p009.hierarchical-rejection-diagnostics.
Do not change README or undertake final aggregate checks; those belong to item 010.

Task-ID: 009-hierarchical-markup-revision-02
Root-Task: 009-hierarchical-markup
Execution-Mode: LEAF_GOAL
Goal-ID: p009.goal.hierarchical-stress-repeatability
Target-Criterion: p009.hierarchical-stress-repeatability
Goal-Success-Evidence: a focused deep or broad hierarchical document is accepted repeatedly through the public CLI with deterministic ACCEPT output and positive work for all eight workers, without hangs or duplicate-induced instability.
Focused-Validation: Run make test-hierarchical-stress-core.
Allowed-Scope: src/recognizer.c, tests/hierarchical_stress_smoke.c, and its Makefile target only.
Baseline-Boundary: acceptance and rejection diagnostics are checkpointed at 66%; only stress/repeatability proof remains for item 009.
Hard-Block-Conditions: None expected; repository-local recognizer and focused-test work must be resolved within scope.
