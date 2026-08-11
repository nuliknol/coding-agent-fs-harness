# Worker Leaf Goal

Task-ID: 003-grammar-ast-revision-02
Goal-ID: p003.goal.left-recursion-validation
Target-Criterion: p003.left-recursion-validation
Goal-Success-Evidence: Grammar validation rejects direct and indirect left recursion with one useful source-located `GRAMMAR_ERROR` diagnostic, while focused cases prove right recursion and epsilon-mediated non-left-recursive grammars remain valid.
Focused-Validation: Run `make test-grammar-ast-core`; extend its focused validation table with direct recursion, indirect recursion, right recursion, and epsilon-safe cases, with exit status 0.
Allowed-Scope: Modify only `Makefile`, `src/grammar_ast.c`, `include/grammar_ast.h`, and `tests/grammar_ast_smoke.c`; preserve parser and symbol validation and do not implement CLI loading, markup, chart recognition, worker pooling, or any recognizer behavior.
Baseline-Boundary: The AST and semantic-resolution criteria are checkpointed at 66%; `pbnfc_grammar_validate` has no independently verified left-recursion analysis.
Hard-Block-Conditions: None expected: no authorization, secret, external service, or unresolved product decision is needed; report a local compiler/toolchain failure with exact command output rather than changing task scope.

Iteration receipts are authoritative in: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/control/goals/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-003-grammar-ast-revision-02.iterations.tsv

## Terminal worker outcome

Outcome: COMPLETE
Result: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/results/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-003-grammar-ast-revision-02.result.md
Published-At: 2026-07-28T04:30:36Z
