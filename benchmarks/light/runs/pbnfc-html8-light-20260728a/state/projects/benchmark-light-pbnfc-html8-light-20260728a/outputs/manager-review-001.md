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