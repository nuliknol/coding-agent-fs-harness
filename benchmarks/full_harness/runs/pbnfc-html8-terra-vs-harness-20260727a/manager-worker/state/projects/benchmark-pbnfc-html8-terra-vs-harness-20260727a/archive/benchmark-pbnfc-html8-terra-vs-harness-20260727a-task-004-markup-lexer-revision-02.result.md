# Task Result

Task-ID: 004-markup-lexer-revision-02
Status: COMPLETED
Goal-ID: p004.goal.markup-lexer-errors-locations
Goal-Outcome: COMPLETE

## Summary

Completed the final markup lexer leaf criterion from the 66% checkpoint. The
lexer now reports deterministic caller-owned diagnostics for malformed markup,
while preserving the previously verified compact tags, quoted values, text
runs, and token locations.

## Modified files

- `include/markup_lexer.h`
- `src/markup_lexer.c`
- `tests/markup_lexer_smoke.c`

## Implemented behavior

- Added the reusable `PbnfcDiagnosticContext` parameter to markup lexer
  initialization.
- Added explicit tag-state validation for opening names, closing names,
  attributes, values, and self-closing endings.
- Rejects unterminated tags, unterminated quoted values, unsupported quote or
  backslash escapes, invalid bytes, invalid punctuation, and invalid tag-state
  transitions.
- Emits exactly one `GRAMMAR_ERROR` diagnostic per failed lexer, with byte,
  line, and column location fields; subsequent calls remain failed without a
  second diagnostic.
- Extended the focused smoke with malformed-input cases covering all required
  error classes, including multiline EOF location tracking.

## Validation performed

- `make test-markup-lexer-core` — PASS; strict C11 build and valid-token,
  quoted-value, text-run, and six-case malformed-input smoke all exited 0.
- `make clean all` — PASS; full project compilation completed under the
  required strict pthread flags.
- `../grader.sh "$PWD"` — the command ran; 2/12 checks passed and the other
  checks reported the pre-existing out-of-scope `grammar recognition is not
  implemented` CLI behavior. No lexer-specific failure was reported.

Starting progress was 66%. The remaining
`p004.markup-lexer-errors-locations` criterion is now advanced to completion;
the two prior checkpointed criteria were preserved and remain covered by the
focused smoke.

## Deviations from assignment

None.

## Remaining concerns

The external grader still exercises later grammar-recognition and CLI work
outside this bounded assignment; those failures were not changed.

## Worker assessment

The leaf goal success evidence passes. The lexer diagnostics API and focused
validation satisfy the assigned malformed-input and exact-location contract.
