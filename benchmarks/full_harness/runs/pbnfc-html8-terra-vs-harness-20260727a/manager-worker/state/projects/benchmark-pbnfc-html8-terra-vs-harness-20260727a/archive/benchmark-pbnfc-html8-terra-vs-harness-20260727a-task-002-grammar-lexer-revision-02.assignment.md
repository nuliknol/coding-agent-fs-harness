# Harness Continuation Context

Task-Root: 002-grammar-lexer
Starting-Progress: 66%
Progress-File: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/control/progress/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-002-grammar-lexer.progress.md
Root-Assignment: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/control/progress/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-002-grammar-lexer.root-assignment.md
Criteria-Definition: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/control/progress/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-002-grammar-lexer.root-assignment.md
Target-Criterion: p002.grammar-lexer-errors

Preserve all previously verified work. This revision may address only the first unmet criterion shown above. Unrelated failures are known limitations and must not broaden this task.

---

# Task: BNF lexer error diagnostics

Task-ID: 002-grammar-lexer-revision-02
Root-Task: 002-grammar-lexer
Project-Plan-Item: 002
Immutable-Root: BNF lexer with directives, token kinds, escapes, alternatives, and epsilon.
Cumulative-Starting-Progress: 66%
Preserve-Verified-Work: p002.grammar-lexer-core and p002.grammar-lexer-terminals-references, including their locations, token kinds, terminal escape handling, and focused smoke.
Execution-Mode: LEAF_GOAL
Goal-ID: p002.goal.grammar-lexer-errors
Target-Criterion: p002.grammar-lexer-errors
Goal-Success-Evidence: For invalid grammar bytes/punctuation, unknown or malformed directives, malformed `$` references, unterminated terminals, and unsupported terminal escapes, the lexer stops deterministically and emits one `GRAMMAR_ERROR ` line containing nonempty useful detail plus the exact byte offset, line, and column through the reusable diagnostics context.
Focused-Validation: Run `make test-grammar-lexer-core`; extend the single focused lexer smoke with a compact table of malformed lexical inputs that checks false return, failed state, one diagnostic line, and expected location fields, with exit status 0.
Allowed-Scope: Modify only `Makefile`, `src/grammar_lexer.c`, `include/grammar_lexer.h`, and `tests/grammar_lexer_smoke.c`; preserve valid token behavior and do not add grammar AST/semantic validation, CLI grammar loading, markup lexing, chart recognition, worker pooling, README work, or an aggregate suite.
Baseline-Boundary: p002 core and terminal/reference criteria are checkpointed at 66%; invalid inputs already return false in some paths, but no focused independently checked contract yet proves one deterministic located diagnostic for every required malformed lexical category.
Hard-Block-Conditions: None expected: no authorization, secret, external service, or unresolved product decision is needed; report a local compiler/toolchain failure with exact command output rather than changing task scope.

## Objective

Complete the final lexer criterion by tightening and testing the error contract. Reuse the existing caller-owned diagnostics module; do not introduce parsing semantics or new subsystem scope.

## Constraints

- Preserve strict C11/pthread build flags and all valid lexer token behavior.
- Keep validation to the existing focused lexer smoke target.
- The diagnostic detail may be concise, but every malformed input must yield exactly one useful, source-located grammar error.
