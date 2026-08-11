# Harness Continuation Context

Task-Root: bnfc-01-foundation
Starting-Progress: 33%
Progress-File: /var/home/mf/coding-agent-fs-harness/benchmark/runs/bnfc-terra-vs-harness-20260727b/manager-worker/state/projects/benchmark-bnfc-terra-vs-harness-20260727b/control/progress/benchmark-bnfc-terra-vs-harness-20260727b-task-bnfc-01-foundation.progress.md
Root-Assignment: /var/home/mf/coding-agent-fs-harness/benchmark/runs/bnfc-terra-vs-harness-20260727b/manager-worker/state/projects/benchmark-bnfc-terra-vs-harness-20260727b/control/progress/benchmark-bnfc-terra-vs-harness-20260727b-task-bnfc-01-foundation.root-assignment.md
Criteria-Definition: /var/home/mf/coding-agent-fs-harness/benchmark/runs/bnfc-terra-vs-harness-20260727b/manager-worker/state/projects/benchmark-bnfc-terra-vs-harness-20260727b/control/progress/benchmark-bnfc-terra-vs-harness-20260727b-task-bnfc-01-foundation.root-assignment.md
Target-Criterion: foundation.cli.required-options

Preserve all previously verified work. This revision may address only the first unmet criterion shown above. Unrelated failures are known limitations and must not broaden this task.

---

# Task: bnfc foundation continuation — CLI argument validation

Task-ID: bnfc-01-foundation-revision-01
Task-Root: bnfc-01-foundation
Project-Plan-Item-ID: 01
Starting-Progress: 33%
Verified-Work-To-Preserve: `foundation.build.strict-c11` is verified: `make clean all` creates executable `bin/bnfc` with `-std=c11 -Wall -Wextra -Werror -pedantic`.
Root-Objective: Complete specification work-breakdown item 1 in ordered leaves, preserving the completed strict C11 build criterion.

Execution-Mode: LEAF_GOAL
Goal-ID: bnfc.goal.01.foundation.cli
Target-Criterion: foundation.cli.required-options
Goal-Success-Evidence: `bin/bnfc` accepts exactly one `--grammar PATH` and one `--input STRING` plus at most one `--start NAME`; every missing option value, missing required option, duplicate option, unknown flag, or positional argument exits 2 and prints one line beginning `GRAMMAR_ERROR `.
Focused-Validation: Run `make clean all`, then manually exercise one representative invocation for each invalid command-line class and verify exit status 2 plus the `GRAMMAR_ERROR ` prefix; also verify a syntactically complete option tuple reaches a non-command-line boundary.
Allowed-Scope: Edit only `Makefile`, `src/`, `include/`, and focused files under `tests/` necessary to parse and validate command-line arguments; preserve the strict-build behavior and do not implement grammar lexing, AST parsing, semantic validation, recognition, or final acceptance/rejection diagnostics.
Baseline-Boundary: `foundation.build.strict-c11` is verified at 33%; the current skeletal `bin/bnfc` ignores all arguments and exits 0, so invalid command lines are not diagnosed as required.
Hard-Block-Conditions: No external dependency or authorization is required; report HARD_BLOCKED only if the repository becomes inaccessible or the governing specification gives irreconcilably contradictory required command-line behavior, with direct evidence.

## Criterion boundary

Implement only `foundation.cli.required-options`. Parse the required CLI shape, retain owned argument data safely for later leaves, and issue concise command-line errors with the exact required error prefix and status. A complete option tuple may stop at a clearly non-command-line placeholder boundary; do not read or lex the grammar file in this leaf. Do not modify the completed build interface or expand into the grammar lexer criterion.
