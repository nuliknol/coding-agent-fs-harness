# Task: BNF lexer foundation

Task-ID: 002-grammar-lexer
Project-Plan-Item: 002
Immutable-Root: BNF lexer with directives, token kinds, escapes, alternatives, and epsilon.
Root-Criterion: p002.grammar-lexer-core
Root-Criterion: p002.grammar-lexer-terminals-references
Root-Criterion: p002.grammar-lexer-errors
Execution-Mode: LEAF_GOAL
Goal-ID: p002.goal.grammar-lexer-core
Target-Criterion: p002.grammar-lexer-core
Goal-Success-Evidence: A reusable grammar-lexer interface and implementation tokenizes insignificant whitespace/comments, `%start` and `%token` directives, bare identifiers, and `::=`, `|`, and `;` punctuation with source locations; a focused lexer smoke target verifies a representative directive/production token sequence deterministically.
Focused-Validation: Run `make test-grammar-lexer-core`; it must build the affected lexer code and pass one focused grammar-token sequence smoke with exit status 0.
Allowed-Scope: Modify only `Makefile`, `src/`, `include/`, and a narrowly scoped `tests/` lexer-smoke source; do not modify the CLI contract, README, specification, or AGENTS instructions, and do not implement grammar AST construction, symbol validation, markup lexing, chart recognition, or worker pooling.
Baseline-Boundary: Plan item 001 is accepted: `bin/pbnfc` builds strictly, validates CLI options, and has reusable diagnostics, but there is no grammar lexer interface, token stream, or lexer-focused smoke target.
Hard-Block-Conditions: None expected: no authorization, secret, external service, or unresolved product decision is needed; report a local compiler/toolchain failure with exact command output rather than broadening scope.

## Objective

Implement only the first ordered lexer criterion. Introduce a small ownership-safe scanner API capable of reading a grammar buffer and yielding the nonterminal/directive/punctuation tokens needed by later parsing. Do not interpret productions or build any AST.

## Ordered root inventory

1. `p002.grammar-lexer-core` — tokenize whitespace/comments, directives, identifiers, and production punctuation with byte/line/column locations.
2. `p002.grammar-lexer-terminals-references` — tokenize single-quoted terminal text with required escapes and `$TOKEN` references.
3. `p002.grammar-lexer-errors` — report invalid characters, malformed directives/references, and terminal/escape lexing errors deterministically through the diagnostic foundation.

## Constraints

- Keep ISO C11 strict flags and pthread linkage intact.
- The focused smoke must be narrow and deterministic; do not introduce an aggregate suite or `make test` yet.
- Preserve accepted plan-item-001 behavior and leave all later compiler/recognizer features unimplemented.
