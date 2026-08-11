# Harness Continuation Context

Task-Root: 003-grammar-ast
Starting-Progress: 66%
Progress-File: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/control/progress/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-003-grammar-ast.progress.md
Root-Assignment: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/control/progress/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-003-grammar-ast.root-assignment.md
Criteria-Definition: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/control/progress/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-003-grammar-ast.root-assignment.md
Target-Criterion: p003.left-recursion-validation

Preserve all previously verified work. This revision may address only the first unmet criterion shown above. Unrelated failures are known limitations and must not broaden this task.

---

# Task: left-recursion validation

Task-ID: 003-grammar-ast-revision-02
Root-Task: 003-grammar-ast
Project-Plan-Item: 003
Immutable-Root: Grammar AST, ownership-safe storage, symbol resolution, and validation.
Cumulative-Starting-Progress: 66%
Preserve-Verified-Work: p003.grammar-ast-parse-storage and p003.symbol-resolution-validation, including AST ownership, symbol resolution, and focused valid/invalid diagnostics.
Execution-Mode: LEAF_GOAL
Goal-ID: p003.goal.left-recursion-validation
Target-Criterion: p003.left-recursion-validation
Goal-Success-Evidence: Grammar validation rejects direct and indirect left recursion with one useful source-located `GRAMMAR_ERROR` diagnostic, while focused cases prove right recursion and epsilon-mediated non-left-recursive grammars remain valid.
Focused-Validation: Run `make test-grammar-ast-core`; extend its focused validation table with direct recursion, indirect recursion, right recursion, and epsilon-safe cases, with exit status 0.
Allowed-Scope: Modify only `Makefile`, `src/grammar_ast.c`, `include/grammar_ast.h`, and `tests/grammar_ast_smoke.c`; preserve parser and symbol validation and do not implement CLI loading, markup, chart recognition, worker pooling, or any recognizer behavior.
Baseline-Boundary: The AST and semantic-resolution criteria are checkpointed at 66%; `pbnfc_grammar_validate` has no independently verified left-recursion analysis.
Hard-Block-Conditions: None expected: no authorization, secret, external service, or unresolved product decision is needed; report a local compiler/toolchain failure with exact command output rather than changing task scope.

## Objective

Complete the final AST root criterion with a safe graph/nullability-aware left-recursion check before recognition.

## Constraints

- Retain strict C11/pthread build and the focused AST smoke target.
- Do not add a broad suite or any parsing/recognizer subsystem.
