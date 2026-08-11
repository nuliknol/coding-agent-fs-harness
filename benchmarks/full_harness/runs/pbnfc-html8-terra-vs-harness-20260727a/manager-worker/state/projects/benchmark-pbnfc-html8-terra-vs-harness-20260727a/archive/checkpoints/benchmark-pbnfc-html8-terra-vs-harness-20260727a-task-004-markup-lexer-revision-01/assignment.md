# Harness Continuation Context

Task-Root: 004-markup-lexer
Starting-Progress: 33%
Progress-File: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/control/progress/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-004-markup-lexer.progress.md
Root-Assignment: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/control/progress/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-004-markup-lexer.root-assignment.md
Criteria-Definition: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/control/progress/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-004-markup-lexer.root-assignment.md
Target-Criterion: p004.markup-lexer-values-text

Preserve all previously verified work. This revision may address only the first unmet criterion shown above. Unrelated failures are known limitations and must not broaden this task.

---

# Task: markup values and text

Task-ID: 004-markup-lexer-revision-01
Root-Task: 004-markup-lexer
Project-Plan-Item: 004
Immutable-Root: Markup lexer for compact tags, text, identifiers, and quoted attributes.
Cumulative-Starting-Progress: 33%
Preserve-Verified-Work: p004.markup-lexer-core-tags, including compact punctuation/identifier tokens, locations, and the focused markup smoke.
Execution-Mode: LEAF_GOAL
Goal-ID: p004.goal.markup-lexer-values-text
Target-Criterion: p004.markup-lexer-values-text
Goal-Success-Evidence: The lexer emits STRING tokens for single- and double-quoted attribute values with quote/backslash escapes and emits one TEXT token for each maximal nonempty outside-tag run while discarding runs containing only ASCII whitespace; a focused smoke proves compact tags, both string quotes, and text-run locations.
Focused-Validation: Run `make test-markup-lexer-core`; extend the focused smoke with both quoted attribute values, escaped quote/backslash content, and non-whitespace text between compact tags, with exit status 0.
Allowed-Scope: Modify only `Makefile`, `src/markup_lexer.c`, `include/markup_lexer.h`, and `tests/markup_lexer_smoke.c`; preserve core token behavior and do not implement grammar integration, chart recognition, worker pooling, README work, or malformed-markup diagnostic completion.
Baseline-Boundary: p004.markup-lexer-core-tags is checkpointed at 33%; the lexer rejects quoted attribute values and outside-tag text instead of producing STRING/TEXT tokens.
Hard-Block-Conditions: None expected: no authorization, secret, external service, or unresolved product decision is needed; report a local compiler/toolchain failure with exact command output rather than changing task scope.

## Objective

Implement only the second markup lexer criterion while preserving compact-tag lexing and locations.

## Constraints

- Keep the existing focused target and strict C11/pthread flags.
- Do not add a broad suite, parser, grammar integration, or recognizer behavior.
