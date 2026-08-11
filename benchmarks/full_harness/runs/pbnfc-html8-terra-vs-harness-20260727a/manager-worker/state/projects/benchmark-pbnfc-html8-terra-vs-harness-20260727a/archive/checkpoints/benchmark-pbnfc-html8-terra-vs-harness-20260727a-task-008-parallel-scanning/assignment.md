# Parallel scanning, deterministic merge/deduplication, and worker statistics

Task-ID: 008-parallel-scanning
Project-Plan-Item: 008
Root-Criterion: p008.parallel-scanning-workers
Root-Criterion: p008.scanning-merge-dedup
Root-Criterion: p008.worker-statistics
Execution-Mode: LEAF_GOAL
Goal-ID: p008.goal.parallel-scanning-workers
Target-Criterion: p008.parallel-scanning-workers
Goal-Success-Evidence: terminal-matching chart items for a scan position are partitioned across all eight persistent workers, produce next-position candidates in private vectors, and a focused scanning smoke confirms all workers performed work.
Focused-Validation: Run make test-parallel-scanning-core.
Allowed-Scope: src/recognizer.c, include/recognizer.h, tests/parallel_scanning_smoke.c, and the corresponding Makefile target only.
Baseline-Boundary: item 007 is accepted: closure prediction/completion and coordinator merge are deterministic; scanner distribution, scan-specific proof, and stats CLI output are not yet accepted for item 008.
Hard-Block-Conditions: None expected; repository-local recognizer, test, or build-target work must be addressed within scope.

Implement only the first criterion. Preserve the accepted closure behavior. Do not modify CLI output/stat formatting yet (reserved for p008.worker-statistics), and do not broaden into hierarchical grammar or final regressions.
