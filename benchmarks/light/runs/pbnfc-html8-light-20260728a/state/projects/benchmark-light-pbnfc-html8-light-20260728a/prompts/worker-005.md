# Persistent goal remediation

Resume the same persistent project goal. The Terra manager rejected completion
and produced the attached completion addendum.

Treat every `ADD-NNN` finding as required work, but keep the immutable original
specification authoritative. Inspect the evidence yourself, then implement all
valid corrections in one coherent pass. Refactor architectural or design
problems when the addendum shows they prevent correct specification behavior.
Do not patch only the visible symptom if the underlying design would leave the
feature incomplete.

After resolving the entire addendum, re-read the complete specification and
look for connected omissions that the manager did not explicitly list. Build,
run the allowed smoke test, and add at most one focused regression test for a
bug you fixed. Continue autonomously until maximum honest completion is reached.

Do not stop after describing a plan or fixing only the first finding. Do not
modify harness state, immutable inputs, or review/addendum files. Follow the
prototype/feature-first development policy; do not expand the task into
production hardening or a large testing project.

# Harness context

Project: `benchmark-light-pbnfc-html8-light-20260728a`

Repository: `/var/home/mf/coding-agent-fs-harness/benchmark/light/runs/pbnfc-html8-light-20260728a/repository`

Immutable specification: `/var/home/mf/coding-agent-fs-harness/benchmark/light/runs/pbnfc-html8-light-20260728a/state/projects/benchmark-light-pbnfc-html8-light-20260728a/inputs/specification.txt`

Development policy: `/var/home/mf/coding-agent-fs-harness/benchmark/light/runs/pbnfc-html8-light-20260728a/state/projects/benchmark-light-pbnfc-html8-light-20260728a/inputs/development-policy.txt`


Manager-authored persistent goal: `/var/home/mf/coding-agent-fs-harness/benchmark/light/runs/pbnfc-html8-light-20260728a/state/projects/benchmark-light-pbnfc-html8-light-20260728a/control/worker-goal.md`

# Completion addendum to resolve

DECISION: REVISE

1. `ADD-006` — Empty quoted terminals and empty markup strings use uninitialized lexeme buffers.

   - `Specification:` A single-quoted terminal matches an exact markup token lexeme; single- and double-quoted attribute values must be recognized as `STRING`.
   - `Evidence:` [src/grammar.c](/var/home/mf/coding-agent-fs-harness/benchmark/light/runs/pbnfc-html8-light-20260728a/repository/src/grammar.c:126) allocates one byte for a quoted terminal but does not initialize it before an empty terminal `''` is passed through `strlen()` at line 350. [src/markup.c](/var/home/mf/coding-agent-fs-harness/benchmark/light/runs/pbnfc-html8-light-20260728a/repository/src/markup.c:138) has the same defect for an empty quoted attribute value such as `x=''`. Exact matching can therefore read indeterminate memory.
   - `Required correction:` Initialize zero-length terminal and string buffers to an empty C string, so an exact empty terminal reliably matches an empty quoted `STRING` lexeme.
   - `Verification:` A grammar containing `S ::= '<' 'a' 'x' '=' '' '>' ;` accepts `<a x=''>` deterministically.

2. `ADD-007` — Rejection diagnostics can violate the required one-line output contract.

   - `Specification:` Rejected markup must print one line beginning `REJECT ` with offset, line, column, and a nonempty `expected=` field.
   - `Evidence:` [src/grammar.c](/var/home/mf/coding-agent-fs-harness/benchmark/light/runs/pbnfc-html8-light-20260728a/repository/src/grammar.c:132) permits newline characters inside quoted terminals, while [src/recognizer.c](/var/home/mf/coding-agent-fs-harness/benchmark/light/runs/pbnfc-html8-light-20260728a/repository/src/recognizer.c:255) inserts terminal text verbatim into `expected`. A rejected grammar containing a terminal such as `'first\nsecond'` emits multiple output lines.
   - `Required correction:` Render expected terminals in a single-line escaped form (or reject unsupported control characters during grammar lexing), while retaining a nonempty expected field.
   - `Verification:` Rejecting empty input against a grammar expecting a newline-containing terminal produces exactly one `REJECT` line.

Baseline checks passed: `make clean all`, `make test`, and `../grader.sh "$PWD"` (12/12).