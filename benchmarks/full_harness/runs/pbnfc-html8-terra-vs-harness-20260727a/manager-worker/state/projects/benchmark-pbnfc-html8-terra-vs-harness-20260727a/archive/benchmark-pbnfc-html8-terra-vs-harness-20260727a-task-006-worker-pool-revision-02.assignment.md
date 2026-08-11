# Harness Continuation Context

Task-Root: 006-worker-pool
Starting-Progress: 66%
Progress-File: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/control/progress/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-006-worker-pool.progress.md
Root-Assignment: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/control/progress/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-006-worker-pool.root-assignment.md
Criteria-Definition: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/control/progress/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-006-worker-pool.root-assignment.md
Target-Criterion: p006.pool-clean-shutdown

Preserve all previously verified work. This revision may address only the first unmet criterion shown above. Unrelated failures are known limitations and must not broaden this task.

---

Task-ID: 006-worker-pool-revision-02
Root-Task: 006-worker-pool
Execution-Mode: LEAF_GOAL
Goal-ID: p006.goal.clean-shutdown
Target-Criterion: p006.pool-clean-shutdown
Goal-Success-Evidence: all eight workers join on normal and error shutdown without races.
Focused-Validation: Run make test-worker-pool-core.
Allowed-Scope: pool module and focused tests only.
Baseline-Boundary: lifecycle and generation protocol checkpointed at 66%.
Hard-Block-Conditions: None expected.
