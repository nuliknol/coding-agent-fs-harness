Implemented the complete ISO C11 `bnfc` project, including grammar lexer/parser, validation, left-recursion detection, fixed-point recognizer, CLI diagnostics, tests, Makefile, README, and generated-artifact ignore rules.

Validation run successfully:

- `make clean all` — passed with strict C11 warnings-as-errors.
- `make test` — passed all focused arithmetic, epsilon, rejection, and recursion tests.
- `../grader.sh "$PWD"` — passed all checks: `SCORE 8/8`.