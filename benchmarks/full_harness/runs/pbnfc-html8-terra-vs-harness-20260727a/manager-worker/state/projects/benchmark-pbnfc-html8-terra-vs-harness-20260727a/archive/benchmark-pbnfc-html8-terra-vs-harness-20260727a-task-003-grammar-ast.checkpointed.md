# Checkpointed Task Increment

Project: benchmark-pbnfc-html8-terra-vs-harness-20260727a

Task-ID: 003-grammar-ast

Task-Root: 003-grammar-ast

Environment-File: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/harness.env

Checkpointed-At: 2026-07-28T04:19:17Z

Artifact-Directory: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/archive/checkpoints/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-003-grammar-ast

## Review notes

# Manager Review Record

Task-ID: 003-grammar-ast
Decision: CHECKPOINT
Progress-Percent: 33%
Improvement-Percent: 33%
Verified-Criterion: p003.grammar-ast-parse-storage
Checkpoint-Path: Makefile
Checkpoint-Path: include/grammar_ast.h
Checkpoint-Path: src/grammar_ast.c
Checkpoint-Path: tests/grammar_ast_smoke.c

## Specification comparison

The new layer parses lexer output into caller-owned grammar declarations, productions, alternatives including epsilon, and typed symbols, with terminal escape decoding and complete freeing of nested storage. Semantic symbol and recursion validation remain separate work.

## Increment verification

- [PASS] p003.grammar-ast-parse-storage — the AST API copies source-derived names, represents empty alternatives and all symbol kinds, and exposes `pbnfc_grammar_free` for ownership-safe cleanup.

## Validation executed

- [PASS] `make test-grammar-ast-core` — exited 0 after compiling the AST/parser with strict flags and checking directives, five productions, alternatives, epsilon, decoded terminal, references, nonterminals, and cleanup path use.

## Scope and regression review

Reviewed `Makefile`, `include/grammar_ast.h`, `src/grammar_ast.c`, and `tests/grammar_ast_smoke.c`; all are permitted. The structural guard requiring directives before productions is not counted as semantic directive-order validation. No CLI loading, markup, chart, or worker-pool code was added.

## Remaining root criteria

- `p003.symbol-resolution-validation` — validate start/directive requirements, duplicate declarations/definitions, undefined nonterminals, and undefined `$TOKEN` references.
- `p003.left-recursion-validation` — detect direct and indirect left recursion while permitting right recursion and epsilon.

## Conclusion

This increment is correct and independently verified, while the root remains incomplete. Checkpoint.

