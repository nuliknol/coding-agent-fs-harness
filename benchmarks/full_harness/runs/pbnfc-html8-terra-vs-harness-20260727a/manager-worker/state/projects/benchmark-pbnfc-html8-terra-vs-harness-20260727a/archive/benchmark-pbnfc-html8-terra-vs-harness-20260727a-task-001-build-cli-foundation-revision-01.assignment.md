# Harness Continuation Context

Task-Root: 001-build-cli-foundation
Starting-Progress: 33%
Progress-File: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/control/progress/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-001-build-cli-foundation.progress.md
Root-Assignment: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/control/progress/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-001-build-cli-foundation.root-assignment.md
Criteria-Definition: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/control/progress/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-001-build-cli-foundation.root-assignment.md
Target-Criterion: p001.cli-option-contract

Preserve all previously verified work. This revision may address only the first unmet criterion shown above. Unrelated failures are known limitations and must not broaden this task.

---

# Task: CLI option contract

Task-ID: 001-build-cli-foundation-revision-01
Root-Task: 001-build-cli-foundation
Project-Plan-Item: 001
Immutable-Root: Strict pthread build skeleton, CLI contract, locations, and diagnostics.
Cumulative-Starting-Progress: 33%
Preserve-Verified-Work: p001.strict-build-skeleton, including the strict pthread Makefile and minimal `src/main.c` executable foundation.
Execution-Mode: LEAF_GOAL
Goal-ID: p001.goal.cli-option-contract
Target-Criterion: p001.cli-option-contract
Goal-Success-Evidence: The executable accepts only `--grammar PATH --input PATH [--start NAME] [--stats]`, rejects missing values, missing required options, duplicate options, and unknown options with exactly one useful `GRAMMAR_ERROR ` line and exit status 2, and does not yet claim grammar recognition for a syntactically complete invocation.
Focused-Validation: Run `make clean all`, then manually verify the no-argument, unknown-option, missing-value, duplicate-option, and complete-option-shape cases; record each exit status and its single diagnostic line.
Allowed-Scope: Modify only `Makefile`, `src/`, and `include/` as needed for deterministic command-line parsing and an inline temporary command-line error reporter; preserve the strict build skeleton and do not implement grammar parsing, markup lexing, chart recognition, worker pooling, or reusable source-location diagnostics.
Baseline-Boundary: Checkpointed p001.strict-build-skeleton is verified at 33%; `bin/pbnfc` currently exits 0 without parsing any arguments, so no documented CLI validation or command-line error contract exists.
Hard-Block-Conditions: None expected: no authorization, secret, external service, or unresolved product decision is needed; report any local compiler or pthread toolchain failure with exact command output rather than changing task scope.

## Objective

Complete only the next ordered root criterion by adding a small deterministic command-line parser. Required option values should be retained only as parsed strings for later phases; do not read grammar/input files or add recognition behavior.

## CLI behavior boundary

- Require one `--grammar PATH` and one `--input PATH`.
- Permit optional `--start NAME` and `--stats` at most once each, in any order.
- Treat unknown options, missing option values, duplicates, and missing required options as command-line errors: one useful `GRAMMAR_ERROR ` line and exit 2.
- A complete option shape may stop at a truthful temporary “not implemented” grammar error with exit 2; it must not pretend to accept/reject markup.

## Constraints

- Retain `-std=c11 -Wall -Wextra -Werror -pedantic -pthread` and the output path `bin/pbnfc`.
- Keep generated output out of source changes and do not modify documentation or specification files.
- Do not repair unrelated later-phase failures or add a broad test suite.
