Resolved ADD-005:

- Prediction now advances callers against already-completed same-position epsilon constituents.
- Added the specified nested epsilon regression to `make test`.
- Empty input now correctly returns `ACCEPT tokens=0`.

Verified:

```text
make clean all
../grader.sh "$PWD"   # SCORE 12/12
make test
```

No remaining specification gaps identified.