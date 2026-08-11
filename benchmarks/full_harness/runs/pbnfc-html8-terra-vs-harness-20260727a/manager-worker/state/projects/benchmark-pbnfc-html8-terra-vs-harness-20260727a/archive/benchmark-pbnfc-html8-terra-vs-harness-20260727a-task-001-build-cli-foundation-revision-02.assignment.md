# Harness Continuation Context

Task-Root: 001-build-cli-foundation
Starting-Progress: 66%
Progress-File: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/control/progress/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-001-build-cli-foundation.progress.md
Root-Assignment: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/control/progress/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-001-build-cli-foundation.root-assignment.md
Criteria-Definition: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/control/progress/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-001-build-cli-foundation.root-assignment.md
Target-Criterion: p001.diagnostic-location-contract

Preserve all previously verified work. This revision may address only the first unmet criterion shown above. Unrelated failures are known limitations and must not broaden this task.

---

# Task: diagnostics and location foundation

Task-ID: 001-build-cli-foundation-revision-02
Root-Task: 001-build-cli-foundation
Project-Plan-Item: 001
Immutable-Root: Strict pthread build skeleton, CLI contract, locations, and diagnostics.
Cumulative-Starting-Progress: 66%
Preserve-Verified-Work: p001.strict-build-skeleton and p001.cli-option-contract, including the strict pthread build and deterministic documented-option validation.
Execution-Mode: LEAF_GOAL
Goal-ID: p001.goal.diagnostic-location-contract
Target-Criterion: p001.diagnostic-location-contract
Goal-Success-Evidence: A reusable header/source diagnostic API defines a value-owned byte/line/column location type and emits deterministic one-line `GRAMMAR_ERROR ` diagnostics through caller-supplied state (no mutable global parser state); the CLI uses that API for its current command-line and placeholder recognition errors.
Focused-Validation: Run `make clean all`, then invoke `bin/pbnfc --grammar grammar --input input` and verify exit 2 with exactly one deterministic `GRAMMAR_ERROR ` line; inspect that the CLI calls the reusable diagnostic API.
Allowed-Scope: Modify only `Makefile`, `src/`, and `include/` to add a small diagnostics/location module and wire the existing CLI to it; preserve option behavior and do not implement grammar parsing, markup lexing, chart recognition, worker pooling, or README work.
Baseline-Boundary: p001.strict-build-skeleton and p001.cli-option-contract are checkpointed at 66%; diagnostics are currently an inline `main.c` function and there is no reusable location representation or diagnostic module.
Hard-Block-Conditions: None expected: no authorization, secret, external service, or unresolved product decision is needed; report any local compiler or pthread toolchain failure with exact command output rather than changing task scope.

## Objective

Finish the final criterion of plan item 001 by extracting a compact diagnostic/location contract suitable for later grammar and markup modules. Keep it self-contained and deterministic; it must not become a lexer or recognizer implementation.

## Required boundary

- Define a public location value containing byte offset, line, and column.
- Define a diagnostic function with explicit caller inputs that can render a `GRAMMAR_ERROR ` line with useful detail and, when supplied, location fields.
- Route existing CLI command-line/placeholder failures through this API, preserving their single-line, exit-2 behavior.
- Do not introduce mutable global parser state, runtime threads, or later-phase parsing work.

## Constraints

- Preserve `bin/pbnfc` and `-std=c11 -Wall -Wextra -Werror -pedantic -pthread`.
- Keep generated build outputs out of source changes; do not modify `README.md`, `SPECIFICATION.md`, `AGENTS.md`, or add a broad test suite.
