# Task Result

Task-ID: 008-parallel-scanning-revision-01
Status: COMPLETED
Goal-ID: p008.goal.scanning-merge-dedup
Goal-Outcome: COMPLETE

## Summary

Completed the scan-specific deterministic merge/deduplication boundary from the 33% checkpoint. Worker-private scan candidates are sorted and compacted before chart insertion, and the focused smoke now exercises duplicate-producing grammar closure followed by parallel scanning and repeatability checks.

## Modified files

- `src/recognizer.c`
- `tests/parallel_scanning_smoke.c`

## Implemented behavior

- Uses the canonical `pbnfc_chart_item_equal` identity predicate when compacting sorted candidates from all persistent worker vectors.
- Preserves deterministic candidate ordering and coordinator-only chart insertion for both closure and scan generations.
- Adds a focused ambiguous/epsilon grammar case that creates duplicate completion candidates before scanning eight terminal chart items.
- Verifies two parallel recognitions accept and produce identical generation, total-work, and scan-work statistics.

## Validation performed

- `make -B test-parallel-scanning-core` — PASS; strict C11/pthread rebuild and focused smoke completed successfully.
- Existing eight-worker scan distribution assertion — PASS for all eight workers.
- Duplicate-producing repeatability assertion — PASS for two identical parallel runs.

Starting progress was 33%. The remaining criterion `p008.scanning-merge-dedup` is independently verified. Previously accepted `p008.parallel-scanning-workers` behavior remains covered and passing.

## Deviations from assignment

None.

## Remaining concerns

The root task’s separate `p008.worker-statistics` criterion remains reserved for a later assignment; CLI statistics formatting was not changed.

## Worker assessment

The leaf goal success evidence passes. The scan merge is deterministic, duplicate chart identities are compacted before insertion, and the focused duplicate-producing smoke confirms repeatable recognition. Current workspace fingerprint: `sha256:c424bda7404b99dd9477e1f9b5dbe93a9d64a1d4412c9dd88dca68d6aa9acbf1`.
