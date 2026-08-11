# Harness Continuation Context

Task-Root: 005-sequential-chart
Starting-Progress: 33%
Progress-File: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/control/progress/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-005-sequential-chart.progress.md
Root-Assignment: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/control/progress/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-005-sequential-chart.root-assignment.md
Criteria-Definition: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/control/progress/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-005-sequential-chart.root-assignment.md
Target-Criterion: p005.sequential-earley-recognition

Preserve all previously verified work. This revision may address only the first unmet criterion shown above. Unrelated failures are known limitations and must not broaden this task.

---

# Task: sequential Earley recognition

Task-ID: 005-sequential-chart-revision-01
Root-Task: 005-sequential-chart
Project-Plan-Item: 005
Immutable-Root: Sequential chart/item semantics serving as a correctness baseline.
Cumulative-Starting-Progress: 33%
Preserve-Verified-Work: p005.chart-item-storage-dedup and its deterministic chart API/smoke.
Execution-Mode: LEAF_GOAL
Goal-ID: p005.goal.sequential-earley-recognition
Target-Criterion: p005.sequential-earley-recognition
Goal-Success-Evidence: A sequential recognizer consumes a validated grammar AST and markup token stream using prediction, completion, scanning, epsilon, and full-input acceptance; a focused smoke accepts nested/right-recursive and epsilon cases and rejects incomplete input.
Focused-Validation: Run `make test-sequential-recognizer`; it must compile and pass the focused sequential recognition smoke with exit status 0.
Allowed-Scope: Modify only `Makefile`, `src/`, `include/`, and focused `tests/` recognizer smoke paths; preserve chart API and do not create pthread workers, parallel rounds, CLI integration, or final rejection-format work.
Baseline-Boundary: p005 chart storage is checkpointed at 33%; no recognizer runs prediction, completion, scanning, or full-stream acceptance.
Hard-Block-Conditions: None expected: no authorization, secret, external service, or unresolved product decision is needed; report local compiler failure exactly rather than broadening scope.

## Objective

Implement only the sequential correctness baseline above the existing grammar, markup, and chart layers.
