# Worker Leaf Goal

Task-ID: 001-build-cli-foundation-revision-01
Goal-ID: p001.goal.cli-option-contract
Target-Criterion: p001.cli-option-contract
Goal-Success-Evidence: The executable accepts only `--grammar PATH --input PATH [--start NAME] [--stats]`, rejects missing values, missing required options, duplicate options, and unknown options with exactly one useful `GRAMMAR_ERROR ` line and exit status 2, and does not yet claim grammar recognition for a syntactically complete invocation.
Focused-Validation: Run `make clean all`, then manually verify the no-argument, unknown-option, missing-value, duplicate-option, and complete-option-shape cases; record each exit status and its single diagnostic line.
Allowed-Scope: Modify only `Makefile`, `src/`, and `include/` as needed for deterministic command-line parsing and an inline temporary command-line error reporter; preserve the strict build skeleton and do not implement grammar parsing, markup lexing, chart recognition, worker pooling, or reusable source-location diagnostics.
Baseline-Boundary: Checkpointed p001.strict-build-skeleton is verified at 33%; `bin/pbnfc` currently exits 0 without parsing any arguments, so no documented CLI validation or command-line error contract exists.
Hard-Block-Conditions: None expected: no authorization, secret, external service, or unresolved product decision is needed; report any local compiler or pthread toolchain failure with exact command output rather than changing task scope.

Iteration receipts are authoritative in: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/control/goals/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-001-build-cli-foundation-revision-01.iterations.tsv

## Terminal worker outcome

Outcome: COMPLETE
Result: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/results/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-001-build-cli-foundation-revision-01.result.md
Published-At: 2026-07-28T03:54:12Z
