# Task Result

Task-ID: bnfc-01-foundation-revision-01
Status: COMPLETED
Goal-ID: bnfc.goal.01.foundation.cli
Goal-Outcome: COMPLETE

## Summary

Implemented the bounded command-line validation criterion while preserving the previously verified strict C11 build foundation.

## Modified files

- `include/cli.h`
- `src/cli.c`
- `src/main.c`

## Implemented behavior

`bin/bnfc` now accepts exactly one `--grammar PATH`, exactly one `--input STRING`, and at most one `--start NAME` in any option order. Missing values, missing required options, duplicate options, unknown flags, and positional arguments produce one `GRAMMAR_ERROR ` line and exit status 2. Valid tuples reach the later-feature placeholder boundary without reading the grammar file, then exit 0. Parsed values are copied and released through the CLI options API for later leaves.

## Validation performed

- `make clean all && test -x bin/bnfc` — passed with `-std=c11 -Wall -Wextra -Werror -pedantic`.
- Focused CLI smoke checks — passed for missing option value, missing required option, duplicate required option, duplicate `--start`, unknown flag, positional argument, complete tuple, and complete tuple with empty input plus `--start`.
- `git diff --check` — passed.
- Generated `bin/` and `build/` artifacts were removed with `make clean` after validation.

Starting progress was 33%; `foundation.build.strict-c11` remains preserved and `foundation.cli.required-options` now has passing focused evidence.

## Deviations from assignment

None.

## Remaining concerns

Grammar lexing, AST parsing, semantic validation, recognition, and final diagnostics remain intentionally out of scope for this leaf.

## Worker assessment

The leaf-goal success evidence passes. Workspace fingerprint after implementation and cleanup: `sha256:7871cadae07050ebb9fe9f5041bcb919c559b00a2f5ad486f46e796be9b57db2`.
