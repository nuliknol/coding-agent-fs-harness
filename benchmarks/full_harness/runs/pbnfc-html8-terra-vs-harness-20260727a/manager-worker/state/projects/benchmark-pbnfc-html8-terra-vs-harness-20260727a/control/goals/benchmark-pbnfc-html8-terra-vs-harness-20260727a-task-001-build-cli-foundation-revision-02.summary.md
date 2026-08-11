# Worker Leaf Goal

Task-ID: 001-build-cli-foundation-revision-02
Goal-ID: p001.goal.diagnostic-location-contract
Target-Criterion: p001.diagnostic-location-contract
Goal-Success-Evidence: A reusable header/source diagnostic API defines a value-owned byte/line/column location type and emits deterministic one-line `GRAMMAR_ERROR ` diagnostics through caller-supplied state (no mutable global parser state); the CLI uses that API for its current command-line and placeholder recognition errors.
Focused-Validation: Run `make clean all`, then invoke `bin/pbnfc --grammar grammar --input input` and verify exit 2 with exactly one deterministic `GRAMMAR_ERROR ` line; inspect that the CLI calls the reusable diagnostic API.
Allowed-Scope: Modify only `Makefile`, `src/`, and `include/` to add a small diagnostics/location module and wire the existing CLI to it; preserve option behavior and do not implement grammar parsing, markup lexing, chart recognition, worker pooling, or README work.
Baseline-Boundary: p001.strict-build-skeleton and p001.cli-option-contract are checkpointed at 66%; diagnostics are currently an inline `main.c` function and there is no reusable location representation or diagnostic module.
Hard-Block-Conditions: None expected: no authorization, secret, external service, or unresolved product decision is needed; report any local compiler or pthread toolchain failure with exact command output rather than changing task scope.

Iteration receipts are authoritative in: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/control/goals/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-001-build-cli-foundation-revision-02.iterations.tsv

## Terminal worker outcome

Outcome: COMPLETE
Result: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/results/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-001-build-cli-foundation-revision-02.result.md
Published-At: 2026-07-28T03:58:54Z
