Resolved ADD-008:

- Escaped newline/control characters in all formatted diagnostics.
- Safely rendered grammar/input paths and `--start` names.
- Added focused CLI one-line diagnostic regressions and updated README.

Verified:

```text
make clean all
../grader.sh "$PWD"   # SCORE 12/12
make test
```

All checks pass.