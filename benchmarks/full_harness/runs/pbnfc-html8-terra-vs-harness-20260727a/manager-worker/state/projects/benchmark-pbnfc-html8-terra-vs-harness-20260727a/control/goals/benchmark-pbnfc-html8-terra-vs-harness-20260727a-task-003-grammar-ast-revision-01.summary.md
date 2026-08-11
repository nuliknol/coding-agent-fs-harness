# Worker Leaf Goal

Task-ID: 003-grammar-ast-revision-01
Goal-ID: p003.goal.symbol-resolution-validation
Target-Criterion: p003.symbol-resolution-validation
Goal-Success-Evidence: A grammar validation API requires exactly the documented directive structure, rejects duplicate token declarations and rule definitions, rejects undefined nonterminal and `$TOKEN` references, and reports each invalid grammar through one useful deterministic `GRAMMAR_ERROR` diagnostic with source location while accepting a representative valid grammar.
Focused-Validation: Run `make test-grammar-ast-core`; extend the focused AST smoke with a compact valid/invalid validation table covering missing or misplaced start declaration, duplicates, undefined nonterminal, and undefined token reference, with exit status 0.
Allowed-Scope: Modify only `Makefile`, `src/grammar_ast.c`, `include/grammar_ast.h`, and `tests/grammar_ast_smoke.c`; preserve AST parsing/ownership and do not implement CLI grammar loading, markup, chart recognition, worker pooling, or left-recursion detection.
Baseline-Boundary: p003.grammar-ast-parse-storage is checkpointed at 33%; AST parsing retains names but lacks an independently checked semantic symbol-validation API.
Hard-Block-Conditions: None expected: no authorization, secret, external service, or unresolved product decision is needed; report a local compiler/toolchain failure with exact command output rather than changing task scope.

Iteration receipts are authoritative in: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/control/goals/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-003-grammar-ast-revision-01.iterations.tsv

## Terminal worker outcome

Outcome: COMPLETE
Result: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/results/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-003-grammar-ast-revision-01.result.md
Published-At: 2026-07-28T04:25:00Z
