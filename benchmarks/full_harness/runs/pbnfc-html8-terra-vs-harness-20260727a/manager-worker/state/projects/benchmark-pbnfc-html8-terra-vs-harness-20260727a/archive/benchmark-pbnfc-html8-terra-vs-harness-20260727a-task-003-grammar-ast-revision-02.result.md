# Task Result

Task-ID: 003-grammar-ast-revision-02
Status: COMPLETED
Goal-ID: p003.goal.left-recursion-validation
Goal-Outcome: COMPLETE

## Summary

Completed the final grammar AST validation criterion from the 66% checkpoint. `pbnfc_grammar_validate` now performs a nullable-aware leading-symbol graph analysis and rejects direct and indirect left recursion with a source-located diagnostic.

## Modified files

- `src/grammar_ast.c`
- `tests/grammar_ast_smoke.c`

## Implemented behavior

- Computes the fixed-point set of nullable productions, including epsilon alternatives.
- Traverses only grammar-leading nonterminal references, continuing across nullable symbols, to detect direct and indirect cycles safely.
- Emits one `GRAMMAR_ERROR left recursion detected` diagnostic at the symbol that closes the detected cycle.
- Preserves prior AST ownership, parsing, declaration ordering, duplicate detection, and symbol-resolution behavior.
- Extends the focused smoke with direct recursion, indirect recursion, nullable-mediated recursion, right recursion, and epsilon-safe cases.
- Updated the prior representative fixture so its retained structure remains valid under the new recursion rule.

## Validation performed

- `make test-grammar-ast-core` — passed; strict C11/pthread compilation and the representative AST plus focused validation table exited 0.
- Workspace fingerprint after work: `sha256:fa9a4d2ec1e567c3a142aa60826f635b310d05cd2d7b749644ad195cda9c66ff`.

Starting progress was 66%. The remaining root criterion `p003.left-recursion-validation` now has passing focused evidence; previously verified AST storage and semantic-resolution behavior was preserved.

## Deviations from assignment

None.

## Remaining concerns

None for the assigned criterion. CLI loading, markup lexing, recognition, and worker-pool behavior remain outside this bounded assignment.

## Worker assessment

The leaf goal is complete and independently verified by the required focused AST smoke. The implementation stayed within the allowed files and did not add recognition behavior or broader tests.
