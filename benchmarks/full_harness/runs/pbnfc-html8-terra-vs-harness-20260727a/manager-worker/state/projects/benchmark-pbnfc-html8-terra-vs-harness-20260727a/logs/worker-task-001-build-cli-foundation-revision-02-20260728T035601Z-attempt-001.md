Completed and published the terminal worker result.

Implemented:

- Reusable `PbnfcLocation` and diagnostic context API.
- Deterministic one-line `GRAMMAR_ERROR` emission.
- CLI wiring through the diagnostic module.
- Strict pthread build integration.

Validation passed: `make clean all`, executable check, and placeholder recognition smoke test (exit 2, exactly one diagnostic line).