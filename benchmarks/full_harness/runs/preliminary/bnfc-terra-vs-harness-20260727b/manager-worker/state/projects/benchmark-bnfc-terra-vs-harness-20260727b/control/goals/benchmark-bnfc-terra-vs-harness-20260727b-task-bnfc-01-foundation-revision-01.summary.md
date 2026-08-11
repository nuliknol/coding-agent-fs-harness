# Worker Leaf Goal

Task-ID: bnfc-01-foundation-revision-01
Goal-ID: bnfc.goal.01.foundation.cli
Target-Criterion: foundation.cli.required-options
Goal-Success-Evidence: `bin/bnfc` accepts exactly one `--grammar PATH` and one `--input STRING` plus at most one `--start NAME`; every missing option value, missing required option, duplicate option, unknown flag, or positional argument exits 2 and prints one line beginning `GRAMMAR_ERROR `.
Focused-Validation: Run `make clean all`, then manually exercise one representative invocation for each invalid command-line class and verify exit status 2 plus the `GRAMMAR_ERROR ` prefix; also verify a syntactically complete option tuple reaches a non-command-line boundary.
Allowed-Scope: Edit only `Makefile`, `src/`, `include/`, and focused files under `tests/` necessary to parse and validate command-line arguments; preserve the strict-build behavior and do not implement grammar lexing, AST parsing, semantic validation, recognition, or final acceptance/rejection diagnostics.
Baseline-Boundary: `foundation.build.strict-c11` is verified at 33%; the current skeletal `bin/bnfc` ignores all arguments and exits 0, so invalid command lines are not diagnosed as required.
Hard-Block-Conditions: No external dependency or authorization is required; report HARD_BLOCKED only if the repository becomes inaccessible or the governing specification gives irreconcilably contradictory required command-line behavior, with direct evidence.

Iteration receipts are authoritative in: /var/home/mf/coding-agent-fs-harness/benchmark/runs/bnfc-terra-vs-harness-20260727b/manager-worker/state/projects/benchmark-bnfc-terra-vs-harness-20260727b/control/goals/benchmark-bnfc-terra-vs-harness-20260727b-task-bnfc-01-foundation-revision-01.iterations.tsv

## Terminal worker outcome

Outcome: COMPLETE
Result: /var/home/mf/coding-agent-fs-harness/benchmark/runs/bnfc-terra-vs-harness-20260727b/manager-worker/state/projects/benchmark-bnfc-terra-vs-harness-20260727b/results/benchmark-bnfc-terra-vs-harness-20260727b-task-bnfc-01-foundation-revision-01.result.md
Published-At: 2026-07-28T03:37:24Z
