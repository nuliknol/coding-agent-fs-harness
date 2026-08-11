Task-ID: 006-worker-pool
Project-Plan-Item: 006
Root-Criterion: p006.pool-lifecycle
Root-Criterion: p006.pool-generation-protocol
Root-Criterion: p006.pool-clean-shutdown
Execution-Mode: LEAF_GOAL
Goal-ID: p006.goal.pool-lifecycle
Target-Criterion: p006.pool-lifecycle
Goal-Success-Evidence: exactly eight persistent pthread workers are created once and exposed by a reusable pool API.
Focused-Validation: Run make test-worker-pool-core with exit 0.
Allowed-Scope: Makefile, src/, include/, focused tests only; no parallel recognizer integration.
Baseline-Boundary: sequential recognizer is accepted and no worker pool exists.
Hard-Block-Conditions: None expected; report local compiler failures exactly.
