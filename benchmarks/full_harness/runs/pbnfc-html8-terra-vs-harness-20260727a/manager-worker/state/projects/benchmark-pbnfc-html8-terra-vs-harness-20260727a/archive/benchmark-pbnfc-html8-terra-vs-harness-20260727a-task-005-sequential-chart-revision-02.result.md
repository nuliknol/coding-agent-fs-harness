# Task Result

Task-ID: 005-sequential-chart-revision-02
Status: COMPLETED
Goal-ID: p005.goal.rejection-diagnostics
Goal-Outcome: COMPLETE

## Summary

Implemented the remaining sequential-recognizer rejection diagnostics slice from the 66% checkpoint. Rejected valid inputs now produce deterministic location and expected-symbol details through an opt-in diagnostic entry point, while the previously verified recognizer API remains available unchanged.

## Modified files

- `include/diagnostics.h`
- `include/recognizer.h`
- `src/diagnostics.c`
- `src/recognizer.c`
- `tests/sequential_recognizer_smoke.c`

## Implemented behavior

- Added `REJECT offset=... line=... column=... expected=...` emission.
- Added diagnosed sequential recognition without changing the existing no-diagnostics wrapper.
- Reports the furthest failed token or deterministic EOF location.
- Collects and deduplicates expected grammar symbols in stable chart order, with an `end of input` fallback.
- Added focused mismatch and EOF rejection assertions.

## Validation performed

- `make test-sequential-recognizer` — passed; the focused smoke verifies nested recognition, epsilon acceptance, mismatch rejection at offset 10/line 1/column 11 with `expected='a'`, and EOF rejection at offset 8/line 1/column 9 with `expected='<'`.
- Final workspace fingerprint: `sha256:7fa65619ccce8c36b0844cd4a60991df8b92460e84619ecf9c471693cb01b90c`.

Starting progress was 66%. The `p005.sequential-rejection-diagnostics` criterion now has its focused success evidence; chart storage and sequential Earley behavior were preserved.

## Deviations from assignment

None.

## Remaining concerns

None within the bounded assignment. CLI integration, threads, parallelism, and full markup recognition remain outside this leaf scope.

## Worker assessment

The assigned rejection-diagnostics criterion is complete and independently verified by the focused sequential recognizer smoke.
