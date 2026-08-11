# Task Result

Task-ID: 001-build-cli-foundation-revision-02
Status: COMPLETED
Goal-ID: p001.goal.diagnostic-location-contract
Goal-Outcome: COMPLETE

## Summary

Completed the diagnostic/location foundation at the 66% checkpoint. The CLI now routes command-line and placeholder recognition failures through a reusable caller-owned diagnostic API while preserving the existing deterministic exit-2 contract.

## Modified files

- `Makefile` — added `src/diagnostics.c` to the build.
- `include/diagnostics.h` — added the public `PbnfcLocation`, diagnostic context, initializer, and emitter declarations.
- `src/diagnostics.c` — implemented deterministic one-line `GRAMMAR_ERROR` emission with optional byte/line/column fields and line-break sanitization.
- `src/main.c` — replaced the inline formatter and passed diagnostic context through option parsing and placeholder recognition failure paths.

## Implemented behavior

- `PbnfcLocation` owns `byte_offset`, `line`, and `column` values.
- `PbnfcDiagnosticContext` carries the caller-selected output stream; no mutable global parser or diagnostic state is used.
- `pbnfc_diagnostic_emit` emits one `GRAMMAR_ERROR ` line, preserves ordinary detail text, and appends `offset=`, `line=`, and `column=` when a location is supplied.
- Existing command-line validation behavior remains unchanged, including exit status 2 and one nonempty diagnostic line.

## Validation performed

- `make clean all` — passed with `-std=c11 -Wall -Wextra -Werror -pedantic -pthread`; produced executable `bin/pbnfc`.
- `test -x bin/pbnfc` — passed.
- `bin/pbnfc --grammar grammar --input input` — exited 2 and emitted exactly one line: `GRAMMAR_ERROR grammar recognition is not implemented`.
- Source inspection with `rg` — passed; confirmed the public byte/line/column fields and that `main.c` calls `pbnfc_diagnostic_emit`.
- Workspace fingerprint after implementation: `sha256:bf34afd3fb69e30533d66b4acb6cb880ec7041176f28ff04de5d59e9144411b3`.

## Deviations from assignment

None.

## Remaining concerns

None for `p001.diagnostic-location-contract`. Grammar parsing, markup recognition, and other later-phase behavior remain intentionally unimplemented.

## Worker assessment

The previously verified strict pthread build skeleton and CLI option contract were preserved. The final root criterion is complete: reusable diagnostics and location representation are present, the CLI is wired to them, and focused validation passes.
