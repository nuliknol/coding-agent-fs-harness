Implemented the complete `pbnfc` project:

- Modular C11 grammar compiler, markup lexer, Earley chart recognizer, and persistent 8-thread pthread pool.
- CLI, diagnostics, start overrides, stats, rejection handling, recursion detection, and allocation cleanup.
- README, focused smoke/regression tests, and generated-artifact exclusions.

Verified with:

```text
make clean all
../grader.sh "$PWD"   # SCORE 12/12
make test
```

Prototype limitation: recognition produces acceptance/rejection only; no parse tree or semantic actions.