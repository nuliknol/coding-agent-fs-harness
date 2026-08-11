# Harness Continuation Context

Task-Root: 003-grammar-ast
Starting-Progress: 33%
Progress-File: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/control/progress/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-003-grammar-ast.progress.md
Root-Assignment: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/control/progress/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-003-grammar-ast.root-assignment.md
Criteria-Definition: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/control/progress/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-003-grammar-ast.root-assignment.md
Target-Criterion: p003.symbol-resolution-validation

Preserve all previously verified work. This revision may address only the first unmet criterion shown above. Unrelated failures are known limitations and must not broaden this task.

---

# Task: grammar symbol validation

Task-ID: 003-grammar-ast-revision-01
Root-Task: 003-grammar-ast
Project-Plan-Item: 003
Immutable-Root: Grammar AST, ownership-safe storage, symbol resolution, and validation.
Cumulative-Starting-Progress: 33%
Preserve-Verified-Work: p003.grammar-ast-parse-storage, including owned AST representation, terminal decoding, epsilon alternatives, and the focused AST smoke.
Execution-Mode: LEAF_GOAL
Goal-ID: p003.goal.symbol-resolution-validation
Target-Criterion: p003.symbol-resolution-validation
Goal-Success-Evidence: A grammar validation API requires exactly the documented directive structure, rejects duplicate token declarations and rule definitions, rejects undefined nonterminal and `$TOKEN` references, and reports each invalid grammar through one useful deterministic `GRAMMAR_ERROR` diagnostic with source location while accepting a representative valid grammar.
Focused-Validation: Run `make test-grammar-ast-core`; extend the focused AST smoke with a compact valid/invalid validation table covering missing or misplaced start declaration, duplicates, undefined nonterminal, and undefined token reference, with exit status 0.
Allowed-Scope: Modify only `Makefile`, `src/grammar_ast.c`, `include/grammar_ast.h`, and `tests/grammar_ast_smoke.c`; preserve AST parsing/ownership and do not implement CLI grammar loading, markup, chart recognition, worker pooling, or left-recursion detection.
Baseline-Boundary: p003.grammar-ast-parse-storage is checkpointed at 33%; AST parsing retains names but lacks an independently checked semantic symbol-validation API.
Hard-Block-Conditions: None expected: no authorization, secret, external service, or unresolved product decision is needed; report a local compiler/toolchain failure with exact command output rather than changing task scope.

## Objective

Implement only the next ordered criterion: validate AST declarations and references before later recursion analysis. Keep diagnostics caller-owned and preserve all accepted AST behavior.

## Constraints

- Keep strict C11/pthread flags and the focused AST smoke target.
- Do not add a broad suite or `make test`.
- Do not attempt left-recursion or recognizer behavior.
