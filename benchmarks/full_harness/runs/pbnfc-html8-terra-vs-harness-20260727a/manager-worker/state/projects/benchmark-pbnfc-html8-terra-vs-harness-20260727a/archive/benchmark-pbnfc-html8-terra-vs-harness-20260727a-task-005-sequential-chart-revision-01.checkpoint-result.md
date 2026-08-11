# Task Result

Task-ID: 005-sequential-chart-revision-01
Status: COMPLETED
Goal-ID: p005.goal.sequential-earley-recognition
Goal-Outcome: COMPLETE

## Summary

Implemented the sequential Earley recognition baseline above the verified chart storage layer. The recognizer closes each chart position through prediction and completion, scans matching markup terminals/token kinds into the next position, handles epsilon alternatives through closure, and accepts only a completed start rule consuming the entire token stream.

## Modified files

- `Makefile`
- `include/recognizer.h`
- `src/recognizer.c`
- `tests/sequential_recognizer_smoke.c`

## Implemented behavior

- Added a reusable `pbnfc_recognize_sequential` API for validated grammar ASTs and caller-owned markup token streams.
- Uses the existing ordered chart sets and all five chart item identity fields for deterministic deduplication.
- Supports exact terminal lexemes, declared markup token-kind references, right recursion, nested expansion, epsilon productions, and full-stream acceptance.
- Returns distinct accepted, rejected, and internal-error results.

## Validation performed

- `make clean all` — passed with `-std=c11 -Wall -Wextra -Werror -pedantic -pthread`.
- `make test-sequential-recognizer` — passed; the focused smoke covers nested/right-recursive acceptance, epsilon acceptance, incomplete input rejection, and trailing incomplete input rejection.

Previously verified chart storage remains used unchanged by the recognizer.

## Deviations from assignment

None. CLI integration, pthread workers, parallel rounds, and final rejection formatting remain outside this bounded criterion.

## Remaining concerns

None for the sequential recognition criterion. The root task still has later parallelism and rejection-diagnostics criteria.

## Worker assessment

The focused success evidence passes and the leaf criterion is complete. Generated build artifacts were removed with `make clean` after validation.
