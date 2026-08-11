Implemented and published the grammar lexer goal.

- Added lexer API and tokenization for grammar syntax, comments, identifiers, terminals, escapes, and line tracking.
- Integrated lexer errors as `GRAMMAR_ERROR` with exit status 2.
- Validation passed: strict build, valid grammar smoke, malformed escape smoke, and `git diff --check`.
