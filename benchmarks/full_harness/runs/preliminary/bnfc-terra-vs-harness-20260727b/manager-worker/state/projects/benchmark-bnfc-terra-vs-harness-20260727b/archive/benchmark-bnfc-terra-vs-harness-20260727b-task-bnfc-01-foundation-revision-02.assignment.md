# Harness Continuation Context

Task-Root: bnfc-01-foundation
Starting-Progress: 66%
Progress-File: /var/home/mf/coding-agent-fs-harness/benchmark/runs/bnfc-terra-vs-harness-20260727b/manager-worker/state/projects/benchmark-bnfc-terra-vs-harness-20260727b/control/progress/benchmark-bnfc-terra-vs-harness-20260727b-task-bnfc-01-foundation.progress.md
Root-Assignment: /var/home/mf/coding-agent-fs-harness/benchmark/runs/bnfc-terra-vs-harness-20260727b/manager-worker/state/projects/benchmark-bnfc-terra-vs-harness-20260727b/control/progress/benchmark-bnfc-terra-vs-harness-20260727b-task-bnfc-01-foundation.root-assignment.md
Criteria-Definition: /var/home/mf/coding-agent-fs-harness/benchmark/runs/bnfc-terra-vs-harness-20260727b/manager-worker/state/projects/benchmark-bnfc-terra-vs-harness-20260727b/control/progress/benchmark-bnfc-terra-vs-harness-20260727b-task-bnfc-01-foundation.root-assignment.md
Target-Criterion: foundation.lexer.grammar-tokens

Preserve all previously verified work. This revision may address only the first unmet criterion shown above. Unrelated failures are known limitations and must not broaden this task.

---

# Task: bnfc foundation continuation — grammar lexer

Task-ID: bnfc-01-foundation-revision-02
Task-Root: bnfc-01-foundation
Project-Plan-Item-ID: 01
Starting-Progress: 66%
Verified-Work-To-Preserve: `foundation.build.strict-c11` and `foundation.cli.required-options` are verified; strict builds produce `bin/bnfc`, and malformed CLI input prints `GRAMMAR_ERROR` with status 2.
Root-Objective: Complete specification work-breakdown item 1 by implementing its final ordered lexer criterion without entering AST parsing or later plan items.

Execution-Mode: LEAF_GOAL
Goal-ID: bnfc.goal.01.foundation.lexer
Target-Criterion: foundation.lexer.grammar-tokens
Goal-Success-Evidence: A lexer API usable by a later parser tokenizes whitespace/comments, `%start`, identifiers, `::=`, `|`, `;`, and quoted terminals with quote/backslash escapes; malformed lexical input produces `GRAMMAR_ERROR ` with exit status 2 and a useful source line number.
Focused-Validation: Run `make clean all`, then run one focused lexer smoke through `bin/bnfc` using a temporary grammar containing comments, `%start`, identifiers, production punctuation, and escaped terminals; verify it exits 0, and verify one malformed terminal/escape exits 2 with `GRAMMAR_ERROR ` and `line=`.
Allowed-Scope: Edit only `Makefile`, `src/`, `include/`, and focused files under `tests/` required for the grammar lexer and its bounded smoke; preserve the build and CLI criteria, and do not implement grammar AST parsing, semantic validation, recognition, or final ACCEPT/REJECT diagnostics.
Baseline-Boundary: At 66%, CLI validation is verified but valid complete option tuples do not open or inspect the grammar path; no grammar tokens or lexical line diagnostics exist.
Hard-Block-Conditions: No external dependency or authorization is required; report HARD_BLOCKED only if the repository becomes inaccessible or the governing specification gives irreconcilably contradictory lexer behavior, with direct evidence.

## Criterion boundary

Implement only `foundation.lexer.grammar-tokens`. The lexer must scan the entire grammar file after CLI validation, retain token values/line positions for the later AST parser, and report malformed lexical input via the required grammar-error prefix and status. It may stop successfully after lexical scanning; it must not interpret production structure, validate references/start symbols/recursion, split the input stream, or recognize tokens. Keep allocations ownership-safe and free lexer/CLI allocations on normal exits.
