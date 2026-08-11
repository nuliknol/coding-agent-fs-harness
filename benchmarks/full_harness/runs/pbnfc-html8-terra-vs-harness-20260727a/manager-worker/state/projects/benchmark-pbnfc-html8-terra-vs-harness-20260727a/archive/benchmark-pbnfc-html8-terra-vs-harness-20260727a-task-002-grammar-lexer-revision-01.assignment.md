# Harness Continuation Context

Task-Root: 002-grammar-lexer
Starting-Progress: 33%
Progress-File: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/control/progress/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-002-grammar-lexer.progress.md
Root-Assignment: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/control/progress/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-002-grammar-lexer.root-assignment.md
Criteria-Definition: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/control/progress/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-002-grammar-lexer.root-assignment.md
Target-Criterion: p002.grammar-lexer-terminals-references

Preserve all previously verified work. This revision may address only the first unmet criterion shown above. Unrelated failures are known limitations and must not broaden this task.

---

# Task: BNF terminals and token references

Task-ID: 002-grammar-lexer-revision-01
Root-Task: 002-grammar-lexer
Project-Plan-Item: 002
Immutable-Root: BNF lexer with directives, token kinds, escapes, alternatives, and epsilon.
Cumulative-Starting-Progress: 33%
Preserve-Verified-Work: p002.grammar-lexer-core, including directive/identifier/punctuation scanning, source locations, and the focused core smoke target.
Execution-Mode: LEAF_GOAL
Goal-ID: p002.goal.grammar-lexer-terminals-references
Target-Criterion: p002.grammar-lexer-terminals-references
Goal-Success-Evidence: The grammar lexer produces distinct tokens for single-quoted terminals and `$TOKEN` references, accepts exactly the required `\\'` and `\\\\` terminal escapes, preserves or exposes the terminal content unambiguously for later parsing, and the focused smoke verifies terminals plus `$IDENT`, `$STRING`, and `$TEXT` alongside core tokens.
Focused-Validation: Run `make test-grammar-lexer-core`; extend that one focused smoke to cover a terminal containing both supported escapes and each declared-token reference, with exit status 0.
Allowed-Scope: Modify only `Makefile`, `src/grammar_lexer.c`, `include/grammar_lexer.h`, and `tests/grammar_lexer_smoke.c`; preserve core lexer behavior and do not implement grammar AST construction, production parsing, markup lexing, chart recognition, worker pooling, README work, or an aggregate test suite.
Baseline-Boundary: p002.grammar-lexer-core is checkpointed at 33%; terminals beginning with a quote and `$TOKEN` references currently reach no successful lexer token path.
Hard-Block-Conditions: None expected: no authorization, secret, external service, or unresolved product decision is needed; report a local compiler/toolchain failure with exact command output rather than changing task scope.

## Objective

Implement only the second ordered criterion. Extend the lexer token model and focused smoke for grammar terminals and declared token-kind references, leaving malformed-terminal/reference diagnostics for the final root criterion.

## Constraints

- Retain strict C11/pthread build flags and the existing core scanner API behavior.
- Do not add grammar semantics, AST ownership, or CLI grammar-file loading.
- The test target remains a single focused lexer smoke, not `make test` or a broad suite.
