# Task: bnfc foundation — build, CLI, and grammar lexer

Task-ID: bnfc-01-foundation
Project-Plan-Item-ID: 01
Root-Objective: Complete specification work-breakdown item 1 without implementing grammar AST parsing, semantic validation, recognition, or final diagnostics beyond what is necessary for command-line and lexer validation.

Root-Criterion: foundation.build.strict-c11
Root-Criterion: foundation.cli.required-options
Root-Criterion: foundation.lexer.grammar-tokens

Execution-Mode: LEAF_GOAL
Goal-ID: bnfc.goal.01.foundation.build
Target-Criterion: foundation.build.strict-c11
Goal-Success-Evidence: `make clean all` exits 0, creates an executable `bin/bnfc`, and the Makefile compiles implementation sources with `-std=c11 -Wall -Wextra -Werror -pedantic`.
Focused-Validation: Run `make clean all && test -x bin/bnfc`; record the command and its zero exit status.
Allowed-Scope: Create or edit only `Makefile`, `src/`, `include/`, and focused files under `tests/` that are necessary for this root; do not edit `SPECIFICATION.md`, `AGENTS.md`, or implement plan items 2–6.
Baseline-Boundary: Baseline inspection found only `README.md`, `SPECIFICATION.md`, and `AGENTS.md`; no Makefile, `src/`, `include/`, `tests/`, or `bin/bnfc` exists, so the focused build command cannot yet succeed.
Hard-Block-Conditions: No external dependency or authorization is required; report HARD_BLOCKED only if the repository becomes inaccessible or the governing specification gives irreconcilably contradictory required build behavior, with direct evidence.

## Criterion inventory

1. `foundation.build.strict-c11`: Add a minimal ISO C11 program and Makefile such that `make clean all` produces executable `bin/bnfc` using all four required strict compiler flags. The binary may be a temporary skeletal executable at this leaf.
2. `foundation.cli.required-options`: Implement the required command-line shape: exactly one `--grammar PATH` and one `--input STRING`, optional single `--start NAME`, with missing values, unknown flags, duplicate required options, and unexpected positional arguments reported as `GRAMMAR_ERROR` and exit status 2. Preserve the build result from criterion 1.
3. `foundation.lexer.grammar-tokens`: Implement a grammar lexer usable by the later parser: whitespace and `#` comments; `%start`; identifiers in the specified ASCII form; `::=`, `|`, and `;`; single-quoted terminals with quote and backslash escapes; and grammar-lexing errors with useful line information and exit status 2. Preserve prior criteria. AST parsing and semantic validation remain out of scope.

## Implementation notes

Use only the ISO C11 standard library. Keep implementation code under `src/` and headers under `include/`. Avoid global mutable parser state and free allocations on normal exits where this root allocates them. Do not add a broad test runner or perform integration behavior from later plan items. The first leaf is deliberately limited to a clean strict build skeleton; leave the required CLI and lexer criteria for their ordered continuations.
