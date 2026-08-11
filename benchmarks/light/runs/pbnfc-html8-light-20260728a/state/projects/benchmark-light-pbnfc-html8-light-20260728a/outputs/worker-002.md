Resolved all addendum findings:

- Replaced the fixed 256-rule recursion DFS with complete rule-count-sized topological cycle detection.
- Added `MARKUP_LITERAL`; punctuation no longer matches `$IDENT`.
- Changed outside-tag text scanning to preserve embedded/edge whitespace and omit only whitespace-only runs.
- Updated README and added focused regressions for whitespace text and punctuation classification.

Verified:

```text
make clean all
make test
../grader.sh "$PWD"   # SCORE 12/12
```

No known specification gaps remain.