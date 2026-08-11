# Task: compact markup lexer foundation

Task-ID: 004-markup-lexer
Project-Plan-Item: 004
Immutable-Root: Markup lexer for compact tags, text, identifiers, and quoted attributes.
Root-Criterion: p004.markup-lexer-core-tags
Root-Criterion: p004.markup-lexer-values-text
Root-Criterion: p004.markup-lexer-errors-locations
Execution-Mode: LEAF_GOAL
Goal-ID: p004.goal.markup-lexer-core-tags
Target-Criterion: p004.markup-lexer-core-tags
Goal-Success-Evidence: A reusable markup lexer tokenizes compact `<`, `>`, `/`, and `=` punctuation plus valid tag/attribute identifiers with byte/line/column locations, without requiring whitespace; a focused smoke checks a compact opening/self-closing tag token sequence.
Focused-Validation: Run `make test-markup-lexer-core`; it must compile the affected lexer and pass one compact-tag sequence/location smoke with exit status 0.
Allowed-Scope: Modify only `Makefile`, `src/`, `include/`, and a focused `tests/` markup-lexer smoke; preserve accepted grammar modules and CLI behavior, and do not implement grammar-to-markup parsing, chart recognition, worker pooling, README work, quoted values, text runs, or error diagnostics beyond the core token interface.
Baseline-Boundary: Grammar plan items 001–003 are accepted; the repository has no markup lexer, markup token kinds, compact-tag scanner, or markup-focused smoke target.
Hard-Block-Conditions: None expected: no authorization, secret, external service, or unresolved product decision is needed; report a local compiler/toolchain failure with exact command output rather than changing task scope.

## Objective

Implement only compact tag punctuation and identifier scanning as the first markup-lexer criterion. Keep the API independent of the grammar recognizer.

## Ordered root inventory

1. `p004.markup-lexer-core-tags` — compact tag punctuation and identifier tokens with locations.
2. `p004.markup-lexer-values-text` — quoted string values and maximal non-whitespace text runs.
3. `p004.markup-lexer-errors-locations` — unterminated tag/value and invalid-byte diagnostics with exact locations.

## Constraints

- Preserve strict C11/pthread flags and existing focused tests.
- Add only the focused markup lexer smoke target; do not add `make test` or recognizer behavior.
