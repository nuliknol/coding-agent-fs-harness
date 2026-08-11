# Accepted Task

Project: benchmark-pbnfc-html8-terra-vs-harness-20260727a

Task-ID: 001-build-cli-foundation-revision-02

Environment-File: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/harness.env

Accepted-At: 2026-07-28T04:00:06Z

## Review notes

# Manager Review Record

Task-ID: 001-build-cli-foundation-revision-02
Decision: ACCEPT
Progress-Percent: 100%
Verified-Criterion: p001.diagnostic-location-contract

## Specification comparison

The completed root provides the required strict pthread build at `bin/pbnfc`, validates the documented command-line option contract, and supplies deterministic reusable diagnostics with byte, line, and column location values without mutable global parser state.

## Acceptance-criteria verification

- [PASS] p001.strict-build-skeleton — prior checkpoint evidence and the current clean build produce executable `bin/pbnfc` with `-std=c11 -Wall -Wextra -Werror -pedantic -pthread`.
- [PASS] p001.cli-option-contract — prior checkpoint evidence established required-option, duplicate, missing-value, and unknown-option errors as single-line `GRAMMAR_ERROR` output with exit 2.
- [PASS] p001.diagnostic-location-contract — `include/diagnostics.h` and `src/diagnostics.c` define a value-owned byte/line/column location plus caller-provided diagnostic context; `src/main.c` routes its errors through `pbnfc_diagnostic_emit`.

## Feature verification

- [PASS] deterministic placeholder diagnostic — a complete CLI invocation emits exactly `GRAMMAR_ERROR grammar recognition is not implemented` once and exits 2, confirming the CLI uses the reusable diagnostic path.

## Validation executed

- [PASS] `make clean all` followed by `bin/pbnfc --grammar grammar --input input` — build exited 0 with all required flags; invocation exited 2 and emitted exactly one expected `GRAMMAR_ERROR` line.

## Scope and regression review

Reviewed `Makefile`, `include/diagnostics.h`, `src/diagnostics.c`, and `src/main.c`. They are all within the final leaf's allowed scope; the modularization preserves the earlier build and CLI behavior and adds no parser, lexer, chart, or worker-pool implementation.

## Conclusion

All required behavior was independently verified. Accept.

