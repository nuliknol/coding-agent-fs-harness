DECISION: REVISE

1. `ADD-008` — Some command-line failures violate the required one-line `GRAMMAR_ERROR` contract.

   - `Specification:` “For command-line … errors, exit 2 and print one line beginning `GRAMMAR_ERROR ` with useful detail.”
   - `Evidence:` `src/main.c` prints unreadable grammar/input paths verbatim; `src/grammar.c:542` includes an undefined `--start` value verbatim. Passing a newline-bearing path or start name produces two output lines, e.g. `bin/pbnfc --grammar $'missing\npath' ...` exits 2 with `GRAMMAR_ERROR cannot read grammar: missing\npath`.
   - `Required correction:` Escape or safely render command-supplied paths and start names so every error path emits exactly one `GRAMMAR_ERROR` line.
   - `Verification:` Run with `--grammar $'missing\npath'` and with `--start $'unknown\nname'`; each must exit 2 and produce exactly one line beginning `GRAMMAR_ERROR `.

Build, project tests, and external grading otherwise pass: `make clean all`, `make test`, and `../grader.sh "$PWD"` (12/12).