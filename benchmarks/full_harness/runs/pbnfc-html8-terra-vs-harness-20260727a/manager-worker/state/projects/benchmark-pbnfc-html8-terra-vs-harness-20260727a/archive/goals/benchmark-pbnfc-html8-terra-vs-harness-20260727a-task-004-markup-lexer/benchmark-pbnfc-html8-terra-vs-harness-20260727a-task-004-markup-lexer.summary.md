# Worker Leaf Goal

Task-ID: 004-markup-lexer
Goal-ID: p004.goal.markup-lexer-core-tags
Target-Criterion: p004.markup-lexer-core-tags
Goal-Success-Evidence: A reusable markup lexer tokenizes compact `<`, `>`, `/`, and `=` punctuation plus valid tag/attribute identifiers with byte/line/column locations, without requiring whitespace; a focused smoke checks a compact opening/self-closing tag token sequence.
Focused-Validation: Run `make test-markup-lexer-core`; it must compile the affected lexer and pass one compact-tag sequence/location smoke with exit status 0.
Allowed-Scope: Modify only `Makefile`, `src/`, `include/`, and a focused `tests/` markup-lexer smoke; preserve accepted grammar modules and CLI behavior, and do not implement grammar-to-markup parsing, chart recognition, worker pooling, README work, quoted values, text runs, or error diagnostics beyond the core token interface.
Baseline-Boundary: Grammar plan items 001–003 are accepted; the repository has no markup lexer, markup token kinds, compact-tag scanner, or markup-focused smoke target.
Hard-Block-Conditions: None expected: no authorization, secret, external service, or unresolved product decision is needed; report a local compiler/toolchain failure with exact command output rather than changing task scope.

Iteration receipts are authoritative in: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/control/goals/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-004-markup-lexer.iterations.tsv

## Terminal worker outcome

Outcome: COMPLETE
Result: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/results/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-004-markup-lexer.result.md
Published-At: 2026-07-28T04:35:31Z
