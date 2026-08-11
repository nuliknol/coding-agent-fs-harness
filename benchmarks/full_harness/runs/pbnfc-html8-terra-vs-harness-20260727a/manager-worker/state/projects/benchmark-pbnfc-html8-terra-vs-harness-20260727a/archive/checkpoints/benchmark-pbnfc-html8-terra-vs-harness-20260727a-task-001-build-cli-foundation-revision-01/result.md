# Task Result

Task-ID: 001-build-cli-foundation-revision-01
Status: COMPLETED
Goal-ID: p001.goal.cli-option-contract
Goal-Outcome: COMPLETE

## Summary

Starting from the 33% checkpoint, implemented the bounded CLI option contract while preserving the verified strict pthread build skeleton.

## Modified files

- `src/main.c` — added deterministic parsing for the four documented options and an inline command-line diagnostic reporter.

## Implemented behavior

- Requires exactly one `--grammar PATH` and one `--input PATH`.
- Supports optional `--start NAME` and `--stats` in any order, each at most once.
- Rejects missing values, duplicate options, unknown options, and positional arguments with one `GRAMMAR_ERROR ` line and exit status 2.
- Rejects missing required options with one `GRAMMAR_ERROR ` line and exit status 2.
- A complete option shape reports the truthful temporary `GRAMMAR_ERROR grammar recognition is not implemented` result with exit status 2; no grammar or input file is read.

## Validation performed

- `make clean all && test -x bin/pbnfc` — PASS, exit 0; compiled and linked with `-std=c11 -Wall -Wextra -Werror -pedantic -pthread`, producing executable `bin/pbnfc`.
- Focused CLI smoke matrix — PASS: no arguments, unknown option, missing `--grammar` value, duplicate `--grammar`, and complete option shape each returned status 2 and exactly one diagnostic line beginning `GRAMMAR_ERROR `.
- `git diff --check` — PASS.

The previously verified `p001.strict-build-skeleton` behavior was preserved by the successful clean rebuild and executable check. The workspace fingerprint after validation is `sha256:1c6b7a7c4f8dd457fd034834ced52a89da57db76e4aaf32742f86bfe644df239`.

## Deviations from assignment

None.

## Remaining concerns

The later `p001.diagnostic-location-contract` and all grammar, markup, recognition, and worker-pool criteria remain unimplemented as required by this bounded assignment.

## Worker assessment

The independently verifiable `p001.cli-option-contract` goal-success evidence passes. The root task is not complete because later ordered criteria remain.
