# Task: grammar AST foundation

Task-ID: 003-grammar-ast
Project-Plan-Item: 003
Immutable-Root: Grammar AST, ownership-safe storage, symbol resolution, and validation.
Root-Criterion: p003.grammar-ast-parse-storage
Root-Criterion: p003.symbol-resolution-validation
Root-Criterion: p003.left-recursion-validation
Execution-Mode: LEAF_GOAL
Goal-ID: p003.goal.grammar-ast-parse-storage
Target-Criterion: p003.grammar-ast-parse-storage
Goal-Success-Evidence: A caller-owned grammar AST API parses the lexer token stream into owned declarations, productions, alternatives (including epsilon), terminal/reference/nonterminal symbols, and frees all owned storage safely; a focused AST smoke parses a representative grammar and checks its retained structure.
Focused-Validation: Run `make test-grammar-ast-core`; it must build the parser/AST layer and pass one representative grammar structure smoke with exit status 0.
Allowed-Scope: Modify only `Makefile`, `src/`, `include/`, and a focused `tests/` AST smoke; preserve lexer APIs and prior test target, and do not implement CLI file loading, markup lexing, chart recognition, worker pooling, symbol resolution, or left-recursion checking.
Baseline-Boundary: Plan items 001 and 002 are accepted; the repository has a complete tokenizing grammar lexer but no grammar AST, parser, owned grammar storage, or AST smoke target.
Hard-Block-Conditions: None expected: no authorization, secret, external service, or unresolved product decision is needed; report a local compiler/toolchain failure with exact command output rather than changing task scope.

## Objective

Implement only the first ordered criterion. Build an ownership-safe grammar AST/parser layer above the existing lexer, retaining all source-derived symbols needed for later resolution without performing semantic validation yet.

## Ordered root inventory

1. `p003.grammar-ast-parse-storage` — parse directives and productions into freeable owned AST storage, including alternatives and epsilon.
2. `p003.symbol-resolution-validation` — resolve rule and `$TOKEN` names, reject undefined/duplicate declarations, and enforce directive ordering.
3. `p003.left-recursion-validation` — detect direct and indirect left recursion before recognition while preserving right recursion and epsilon.

## Constraints

- Preserve strict C11/pthread builds and existing focused lexer smoke.
- Add only a focused AST smoke target, not a broad suite or `make test`.
- Do not add markup or recognizer implementation.
