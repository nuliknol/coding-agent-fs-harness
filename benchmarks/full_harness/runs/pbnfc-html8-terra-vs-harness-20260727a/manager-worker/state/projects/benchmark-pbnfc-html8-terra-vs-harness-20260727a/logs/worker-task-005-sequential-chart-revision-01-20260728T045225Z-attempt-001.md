Implemented and published `p005.goal.sequential-earley-recognition` as COMPLETE.

Added:

- Sequential Earley recognizer with prediction, completion, scanning, epsilon handling, and full-stream acceptance.
- Focused `make test-sequential-recognizer` smoke.
- Strict build integration.

Validation passed:

- `make clean all`
- `make test-sequential-recognizer`