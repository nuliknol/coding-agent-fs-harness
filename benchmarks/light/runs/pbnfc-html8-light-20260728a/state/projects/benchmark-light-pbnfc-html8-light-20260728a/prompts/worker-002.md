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

1. `ADD-001` — Indirect left-recursion detection has a fixed 256-rule depth limit.

   - `Specification:` “Detect direct and indirect left recursion before recognition.”
   - `Evidence:` [`src/grammar.c`](/var/home/mf/coding-agent-fs-harness/benchmark/light/runs/pbnfc-html8-light-20260728a/repository/src/grammar.c:477) uses `size_t stack[256]`; at line 497 it silently declines to traverse a further edge when the stack is full. A 257-rule cycle is therefore accepted instead of producing `GRAMMAR_ERROR`.
   - `Required correction:` Use traversal storage sized for the grammar’s rule count (or another complete cycle-detection algorithm), and reject cycles of any supported grammar size.
   - `Verification:` A generated grammar containing a 257-rule indirect left-recursion cycle exits 2 with one `GRAMMAR_ERROR` line.

2. `ADD-002` — Markup punctuation is incorrectly exposed as `$IDENT`.

   - `Specification:` Identifiers have kind `IDENT`; `$IDENT` matches the declared markup token kind regardless of lexeme. `<`, `>`, `/`, and `=` are exact literal lexemes.
   - `Evidence:` [`src/markup.c`](/var/home/mf/coding-agent-fs-harness/benchmark/light/runs/pbnfc-html8-light-20260728a/repository/src/markup.c:97) and [line 124](/var/home/mf/coding-agent-fs-harness/benchmark/light/runs/pbnfc-html8-light-20260728a/repository/src/markup.c:124) create punctuation tokens as `MARKUP_IDENT`; [`include/markup.h`](/var/home/mf/coding-agent-fs-harness/benchmark/light/runs/pbnfc-html8-light-20260728a/repository/include/markup.h:7) has no literal-token kind. Consequently, a grammar `S ::= $IDENT $IDENT $IDENT ;` accepts `<a>`, although only `a` is an identifier.
   - `Required correction:` Represent punctuation as a distinct literal/punctuation token category and ensure `$IDENT` matches only identifier tokens while quoted grammar terminals continue matching punctuation lexemes.
   - `Verification:` `%token IDENT` with `S ::= $IDENT $IDENT $IDENT ;` rejects `<a>`; `S ::= '<' $IDENT '>' ;` accepts it.

3. `ADD-003` — Outside-tag text tokenization discards and splits ASCII whitespace instead of preserving maximal text runs.

   - `Specification:` “Outside tags, each nonempty maximal text run is one `TEXT` token. Preserve its byte location while ignoring runs that contain only ASCII whitespace.”
   - `Evidence:` [`src/markup.c`](/var/home/mf/coding-agent-fs-harness/benchmark/light/runs/pbnfc-html8-light-20260728a/repository/src/markup.c:101) discards every whitespace character, and [line 105](/var/home/mf/coding-agent-fs-harness/benchmark/light/runs/pbnfc-html8-light-20260728a/repository/src/markup.c:105) terminates a text token at whitespace. Thus `hello world` becomes two tokens, not one `TEXT` token with that lexeme and its original location.
   - `Required correction:` Scan from one `<` delimiter to the next as one run, retain embedded/edge ASCII whitespace if the run contains any non-whitespace byte, and omit only an all-whitespace run.
   - `Verification:` A grammar terminal `'hello world'` accepts `<p>hello world</p>`; a whitespace-only region between tags produces no `$TEXT` token.

The required `make clean all`, `../grader.sh "$PWD"` (12/12), and `make test` currently pass, but they do not cover these specification violations.