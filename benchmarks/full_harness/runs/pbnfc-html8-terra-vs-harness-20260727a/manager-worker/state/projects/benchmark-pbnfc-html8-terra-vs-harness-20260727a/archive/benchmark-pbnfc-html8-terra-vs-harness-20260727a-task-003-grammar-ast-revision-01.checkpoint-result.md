# Task Result

Task-ID: 003-grammar-ast-revision-01
Status: COMPLETED
Goal-ID: p003.goal.symbol-resolution-validation
Goal-Outcome: COMPLETE

## Summary

Advanced the checkpointed grammar AST work from 33% with an independently verifiable declaration and symbol validation API. Previously verified parsing, owned storage, terminal decoding, epsilon alternatives, and cleanup remain unchanged.

## Modified files

- `include/grammar_ast.h`
- `src/grammar_ast.c`
- `tests/grammar_ast_smoke.c`

## Implemented behavior

- Added `pbnfc_grammar_validate` with caller-supplied diagnostics and no ownership transfer.
- Requires exactly one `%start` declaration, with `%start` before all `%token` directives.
- Rejects duplicate token declarations and duplicate rule definitions.
- Rejects an undefined start rule, undefined bare nonterminals, and undefined `$TOKEN` references.
- Stops after the first deterministic validation failure and emits one `GRAMMAR_ERROR` diagnostic with the offending AST source location.
- Extended the focused smoke with a valid grammar and invalid cases for missing/misplaced/duplicate start declarations, duplicate tokens/rules, and undefined references.

## Validation performed

- `make test-grammar-ast-core` — PASS; strict AST build and valid/invalid validation table exited 0.
- `make clean all` — PASS; complete strict C11/pthread build exited 0.
- Workspace fingerprint after work: `sha256:33b36a38af4f2f101fa70ff3e19239b67e98f47ce54eb7063d1d5b0ae1cd40be`

## Deviations from assignment

None.

## Remaining concerns

Left-recursion detection and later recognizer work remain outside this bounded criterion.

## Worker assessment

COMPLETE. The target criterion's focused success evidence passes from the 33% checkpoint, and prior AST parsing/ownership behavior is covered by the same passing smoke.
