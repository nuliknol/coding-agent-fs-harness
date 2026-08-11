# Task Result

Task-ID: 005-sequential-chart
Status: COMPLETED
Goal-ID: p005.goal.chart-item-storage-dedup
Goal-Outcome: COMPLETE

## Summary

Starting progress was 0%. Implemented the first sequential recognition layer: an owned chart with one ordered item set per current position and deterministic five-field item identity/deduplication.

## Modified files

- `include/chart.h`
- `src/chart.c`
- `tests/chart_core_smoke.c`
- `Makefile`

## Implemented behavior

- Added `PbnfcChartItem` keyed by production, alternative, dot, origin, and current position.
- Added chart initialization/freeing, position-set accessors, stable insertion-order iteration, bounds checks, and allocation-safe growth.
- Added distinct inserted, duplicate, and error insertion results; duplicate items are never appended.
- Added `make test-chart-core` and a focused smoke covering insertion order, duplicate suppression, empty/out-of-range access, invalid insertion, and cleanup.
- Linked the chart module into the strict main build while leaving grammar and markup lexers unchanged.

## Validation performed

- `make clean all` — passed; strict C11/pthread compilation and `bin/pbnfc` link succeeded.
- `make test-chart-core` — passed with exit status 0.
- Workspace fingerprint after validation: `sha256:9e9cb2824f7475ea74274d244d957f623c369e91ed7aa9e6721b0dff77a44cd8`.

## Deviations from assignment

None.

## Remaining concerns

Sequential prediction/completion/scanning, rejection diagnostics, and parallel worker behavior remain future root inventory items and were intentionally not implemented in this bounded goal.

## Worker assessment

The assigned chart-item-storage/deduplication criterion is complete. Existing source modules compiled successfully alongside the new chart module, preserving the accepted lexer/AST baseline.
