Resolved ADD-006 and ADD-007:

- Empty grammar terminals and markup strings now initialize as `""`.
- Rejection expectations escape control characters, preserving the one-line output contract.
- Added focused regressions for empty strings and newline-containing terminals.
- Updated README diagnostics documentation.

Verified:

```text
make clean all
../grader.sh "$PWD"   # SCORE 12/12
make test
```

All checks pass.