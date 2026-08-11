Implemented the complete `pbnfc` project with C11, pthread worker pool, grammar/markup lexers, Earley recognition, tests, and documentation.

Final checks run:

- `make clean all` — passed with strict warnings enabled.
- `make test` — passed.
- `../grader.sh "$PWD"` — passed all checks, `SCORE 12/12`.