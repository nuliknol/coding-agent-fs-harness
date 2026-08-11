# Task: sequential chart foundation

Task-ID: 005-sequential-chart
Project-Plan-Item: 005
Immutable-Root: Sequential chart/item semantics serving as a correctness baseline.
Root-Criterion: p005.chart-item-storage-dedup
Root-Criterion: p005.sequential-earley-recognition
Root-Criterion: p005.sequential-rejection-diagnostics
Execution-Mode: LEAF_GOAL
Goal-ID: p005.goal.chart-item-storage-dedup
Target-Criterion: p005.chart-item-storage-dedup
Goal-Success-Evidence: A reusable sequential chart API owns ordered item sets keyed by production, alternative, dot, origin, and current position; it deterministically deduplicates inserts and exposes stable iteration, verified by a focused chart-storage smoke.
Focused-Validation: Run `make test-chart-core`; it must compile the chart module and pass a focused insertion/deduplication/order smoke with exit status 0.
Allowed-Scope: Modify only `Makefile`, `src/`, `include/`, and a focused `tests/` chart smoke; preserve grammar/markup lexers and do not implement CLI file loading, threads, parallel rounds, or full markup recognition yet.
Baseline-Boundary: Plan items 001–004 are accepted; grammars and markup tokenize independently but there is no chart item representation, chart set, deduplication, or sequential recognition baseline.
Hard-Block-Conditions: None expected: no authorization, secret, external service, or unresolved product decision is needed; report a local compiler/toolchain failure with exact command output rather than changing task scope.

## Objective

Implement only deterministic chart-item storage and deduplication as the first sequential recognition layer.

## Ordered root inventory

1. `p005.chart-item-storage-dedup` — ordered owned chart sets and deterministic item deduplication.
2. `p005.sequential-earley-recognition` — sequential prediction, completion, scanning, epsilon, and full-stream acceptance.
3. `p005.sequential-rejection-diagnostics` — deterministic rejected-input offset/line/column/expected diagnostics.

## Constraints

- Preserve strict C11/pthread flags and existing focused tests.
- Add a focused chart smoke only; do not implement threads, parallelism, or a broad suite.
