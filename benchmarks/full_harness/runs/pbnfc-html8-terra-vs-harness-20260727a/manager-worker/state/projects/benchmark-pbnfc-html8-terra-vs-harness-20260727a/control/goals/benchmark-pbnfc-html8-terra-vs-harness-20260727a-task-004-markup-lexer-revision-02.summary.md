# Worker Leaf Goal

Task-ID: 004-markup-lexer-revision-02
Goal-ID: p004.goal.markup-lexer-errors-locations
Target-Criterion: p004.markup-lexer-errors-locations
Goal-Success-Evidence: Unterminated tags, unterminated quoted values, unsupported value escapes, invalid bytes/punctuation, and invalid tag-state transitions each stop the lexer and emit exactly one useful `GRAMMAR_ERROR ` diagnostic with exact byte offset, line, and column through the reusable diagnostic API.
Focused-Validation: Run `make test-markup-lexer-core`; extend the focused smoke with a compact malformed-input table that checks false return, failed state, one diagnostic line, and exact location fields, with exit status 0.
Allowed-Scope: Modify only `Makefile`, `src/markup_lexer.c`, `include/markup_lexer.h`, and `tests/markup_lexer_smoke.c`; preserve valid lexer behavior and do not add grammar integration, chart recognition, worker pooling, README work, or broad testing.
Baseline-Boundary: The first two markup lexer criteria are checkpointed at 66%; malformed inputs can fail but have no independently checked deterministic diagnostic/location contract.
Hard-Block-Conditions: None expected: no authorization, secret, external service, or unresolved product decision is needed; report a local compiler/toolchain failure with exact command output rather than changing task scope.

Iteration receipts are authoritative in: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/control/goals/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-004-markup-lexer-revision-02.iterations.tsv

## Terminal worker outcome

Outcome: COMPLETE
Result: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/results/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-004-markup-lexer-revision-02.result.md
Published-At: 2026-07-28T04:47:51Z
