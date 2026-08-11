# Worker Leaf Goal

Task-ID: 002-grammar-lexer-revision-02
Goal-ID: p002.goal.grammar-lexer-errors
Target-Criterion: p002.grammar-lexer-errors
Goal-Success-Evidence: For invalid grammar bytes/punctuation, unknown or malformed directives, malformed `$` references, unterminated terminals, and unsupported terminal escapes, the lexer stops deterministically and emits one `GRAMMAR_ERROR ` line containing nonempty useful detail plus the exact byte offset, line, and column through the reusable diagnostics context.
Focused-Validation: Run `make test-grammar-lexer-core`; extend the single focused lexer smoke with a compact table of malformed lexical inputs that checks false return, failed state, one diagnostic line, and expected location fields, with exit status 0.
Allowed-Scope: Modify only `Makefile`, `src/grammar_lexer.c`, `include/grammar_lexer.h`, and `tests/grammar_lexer_smoke.c`; preserve valid token behavior and do not add grammar AST/semantic validation, CLI grammar loading, markup lexing, chart recognition, worker pooling, README work, or an aggregate suite.
Baseline-Boundary: p002 core and terminal/reference criteria are checkpointed at 66%; invalid inputs already return false in some paths, but no focused independently checked contract yet proves one deterministic located diagnostic for every required malformed lexical category.
Hard-Block-Conditions: None expected: no authorization, secret, external service, or unresolved product decision is needed; report a local compiler/toolchain failure with exact command output rather than changing task scope.

Iteration receipts are authoritative in: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/control/goals/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-002-grammar-lexer-revision-02.iterations.tsv

## Terminal worker outcome

Outcome: COMPLETE
Result: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/results/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-002-grammar-lexer-revision-02.result.md
Published-At: 2026-07-28T04:12:36Z
