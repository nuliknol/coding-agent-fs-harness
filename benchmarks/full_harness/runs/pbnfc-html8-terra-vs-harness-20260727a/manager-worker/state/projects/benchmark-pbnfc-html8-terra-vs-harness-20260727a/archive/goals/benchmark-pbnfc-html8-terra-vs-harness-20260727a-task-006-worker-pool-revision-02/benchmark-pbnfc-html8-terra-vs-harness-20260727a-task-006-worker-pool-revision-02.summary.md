# Worker Leaf Goal

Task-ID: 006-worker-pool-revision-02
Goal-ID: p006.goal.clean-shutdown
Target-Criterion: p006.pool-clean-shutdown
Goal-Success-Evidence: all eight workers join on normal and error shutdown without races.
Focused-Validation: Run make test-worker-pool-core.
Allowed-Scope: pool module and focused tests only.
Baseline-Boundary: lifecycle and generation protocol checkpointed at 66%.
Hard-Block-Conditions: None expected.

Iteration receipts are authoritative in: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/control/goals/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-006-worker-pool-revision-02.iterations.tsv

## Terminal worker outcome

Outcome: COMPLETE
Result: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/results/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-006-worker-pool-revision-02.result.md
Published-At: 2026-07-28T05:14:37Z
