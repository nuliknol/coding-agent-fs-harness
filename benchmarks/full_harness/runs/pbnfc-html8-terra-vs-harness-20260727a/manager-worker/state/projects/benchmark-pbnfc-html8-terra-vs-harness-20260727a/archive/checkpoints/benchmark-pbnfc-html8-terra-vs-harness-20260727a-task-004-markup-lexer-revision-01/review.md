# Manager Review Record

Task-ID: 004-markup-lexer-revision-01
Decision: CHECKPOINT
Progress-Percent: 66%
Improvement-Percent: 33%
Verified-Criterion: p004.markup-lexer-values-text
Checkpoint-Path: include/markup_lexer.h
Checkpoint-Path: src/markup_lexer.c
Checkpoint-Path: tests/markup_lexer_smoke.c

## Specification comparison

The lexer now scans both required quoted attribute forms with quote/backslash escapes and emits maximal non-whitespace outside-tag text runs while retaining compact token locations.

## Increment verification

- [PASS] p004.markup-lexer-values-text — distinct STRING/TEXT tokens preserve source lexemes and locations; whitespace-only outside-tag slices produce no text token.

## Validation executed

- [PASS] `make test-markup-lexer-core` — exited 0 after checking compact tags, both value quote styles, escapes, text runs, and locations.

## Scope and regression review

Reviewed markup lexer header/source/smoke only; changes are in scope and add no grammar integration, recognizer, or worker pool work.

## Remaining root criteria

- `p004.markup-lexer-errors-locations` — report malformed tag/value and invalid-byte errors with exact locations.

## Conclusion

This increment is correct and independently verified, while the root remains incomplete. Checkpoint.
