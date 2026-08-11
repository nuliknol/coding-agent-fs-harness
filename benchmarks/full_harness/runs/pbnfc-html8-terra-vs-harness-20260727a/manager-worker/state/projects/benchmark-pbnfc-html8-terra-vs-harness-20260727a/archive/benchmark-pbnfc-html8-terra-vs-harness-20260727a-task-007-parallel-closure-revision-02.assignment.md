# Harness Continuation Context

Task-Root: 007-parallel-closure
Starting-Progress: 66%
Progress-File: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/control/progress/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-007-parallel-closure.progress.md
Root-Assignment: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/control/progress/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-007-parallel-closure.root-assignment.md
Criteria-Definition: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/control/progress/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-007-parallel-closure.root-assignment.md
Target-Criterion: p007.deterministic-closure-merge

Preserve all previously verified work. This revision may address only the first unmet criterion shown above. Unrelated failures are known limitations and must not broaden this task.

---

# Harness Continuation Context

Task-Root: 007-parallel-closure
Starting-Progress: 66%
Preserve verified criteria: p007.thread-local-candidates and p007.parallel-prediction-completion.
Unrelated scanner, CLI statistics, hierarchical-grammar, and full-regression work remain outside this leaf.

Task-ID: 007-parallel-closure-revision-02
Root-Task: 007-parallel-closure
Execution-Mode: LEAF_GOAL
Goal-ID: p007.goal.deterministic-closure-merge
Target-Criterion: p007.deterministic-closure-merge
Goal-Success-Evidence: coordinator deterministically orders and deduplicates all worker closure candidates before chart insertion, with the focused smoke showing repeatable acceptance.
Focused-Validation: Run make test-parallel-closure-core.
Allowed-Scope: src/recognizer.c and tests/parallel_closure_smoke.c only, plus a Makefile target only if the focused smoke requires it.
Baseline-Boundary: p007.thread-local-candidates and p007.parallel-prediction-completion are checkpointed at 66%.
Hard-Block-Conditions: None expected; repository-local implementation or test changes are not hard blocks.
