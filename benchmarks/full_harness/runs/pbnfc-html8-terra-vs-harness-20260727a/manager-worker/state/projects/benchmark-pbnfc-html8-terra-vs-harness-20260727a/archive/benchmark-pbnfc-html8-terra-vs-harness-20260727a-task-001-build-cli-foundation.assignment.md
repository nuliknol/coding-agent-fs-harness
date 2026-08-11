# Task: strict build and CLI foundation

Task-ID: 001-build-cli-foundation
Project-Plan-Item: 001
Immutable-Root: Strict pthread build skeleton, CLI contract, locations, and diagnostics.
Root-Criterion: p001.strict-build-skeleton
Root-Criterion: p001.cli-option-contract
Root-Criterion: p001.diagnostic-location-contract
Execution-Mode: LEAF_GOAL
Goal-ID: p001.goal.strict-build-skeleton
Target-Criterion: p001.strict-build-skeleton
Goal-Success-Evidence: `make clean all` exits 0, creates executable `bin/pbnfc`, and its compile/link commands use ISO C11 strict warning flags with pthread support.
Focused-Validation: Run `make clean all && test -x bin/pbnfc`; record the exact exit status and resulting binary path.
Allowed-Scope: Create or modify only `Makefile`, `src/`, and `include/` to provide the minimal executable build skeleton; do not implement grammar or markup recognition and do not modify `README.md`, `SPECIFICATION.md`, or `AGENTS.md`.
Baseline-Boundary: The seed repository contains only documentation and no Makefile, source tree, header tree, or `bin/pbnfc`; the focused build command cannot yet be run.
Hard-Block-Conditions: None expected: no authorization, secret, external service, or unresolved product decision is needed; report any local compiler or pthread toolchain failure with its exact command output rather than broadening scope.

## Objective

Implement only the first root criterion. Establish a clean ISO C11/pthread build foundation that emits the required executable path. A minimal placeholder program is sufficient; do not claim recognition behavior.

## Ordered root inventory

1. `p001.strict-build-skeleton` — strict `make clean all` builds executable `bin/pbnfc` from sources under `src/` with pthread support.
2. `p001.cli-option-contract` — the executable validates the documented option shape and reports command-line errors through the required exit/error contract.
3. `p001.diagnostic-location-contract` — reusable diagnostic/location interfaces support deterministic `GRAMMAR_ERROR` output foundations without mutable global parser state.

## Constraints

- Use ISO C11 and POSIX pthreads only; compilation must include `-std=c11 -Wall -Wextra -Werror -pedantic -pthread`.
- Keep the implementation deliberately minimal and warning-free; do not add generated artifacts to version control.
- Do not add a broad test suite or attempt later grammar, lexer, recognizer, worker-pool, or documentation phases.
- Preserve every file outside the allowed scope.
