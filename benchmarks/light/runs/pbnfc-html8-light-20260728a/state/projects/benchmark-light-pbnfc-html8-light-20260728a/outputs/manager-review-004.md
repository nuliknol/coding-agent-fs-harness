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