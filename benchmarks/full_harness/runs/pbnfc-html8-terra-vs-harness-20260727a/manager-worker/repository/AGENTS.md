# Benchmark repository guidance

Implement the complete project described in `SPECIFICATION.md` in ISO C11 with
POSIX pthreads. Use no other external libraries. Keep generated artifacts out of version
control.  The required final external checks are:

```bash
make clean all
../grader.sh "$PWD"
```

The grader is outside the repository during a benchmark run.  Do not change the
required command-line interface or tailor behavior to individual grammar files.
Add your own focused tests under `tests/`, but the external grader is authoritative.
