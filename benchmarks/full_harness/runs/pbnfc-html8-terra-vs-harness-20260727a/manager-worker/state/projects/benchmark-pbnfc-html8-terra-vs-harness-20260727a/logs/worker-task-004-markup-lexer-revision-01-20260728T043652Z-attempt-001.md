Implemented and published the markup lexer value/text revision.

- Added quoted `STRING` tokens with escapes.
- Added maximal outside-tag `TEXT` tokens.
- Preserved existing compact-tag behavior and locations.
- Focused validation passed: `make clean test-markup-lexer-core`.
- Result published via `worker-complete-task`.