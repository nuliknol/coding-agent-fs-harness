Task-ID: 007-parallel-closure
Project-Plan-Item: 007
Root-Criterion: p007.thread-local-candidates
Root-Criterion: p007.parallel-prediction-completion
Root-Criterion: p007.deterministic-closure-merge
Execution-Mode: LEAF_GOAL
Goal-ID: p007.goal.thread-local-candidates
Target-Criterion: p007.thread-local-candidates
Goal-Success-Evidence: eight workers produce isolated candidate buffers for chart work.
Focused-Validation: Run make test-parallel-closure-core.
Allowed-Scope: parallel recognizer, pool, build, focused tests only.
Baseline-Boundary: sequential recognizer and persistent pool are accepted.
Hard-Block-Conditions: None expected.
