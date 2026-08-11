# pbnfc

`pbnfc` compiles a compact BNF grammar and recognizes HTML-like markup.

```sh
make clean all
bin/pbnfc --grammar grammar.bnf --input page.html [--start Name] [--stats]
```

Grammar files begin with `%start Name`, can declare `%token IDENT`, `%token
STRING`, and `%token TEXT`, and use `::=`, `|`, `;`, quoted literal terminals,
`$TOKEN` kind terminals, and empty alternatives. `#` starts a comment. Quoted
literals support `\\` and `\'`.

The markup lexer recognizes compact tags, identifiers, quoted attribute values,
and non-whitespace text runs. Tags and quotes must terminate. The grammar is
responsible for tag pairing and allowable hierarchy.

Recognition is Earley-style. A single persistent pool of eight pthread workers
processes closure and scanning waves. Workers only append thread-local chart
candidates; the coordinator stable-sorts and deduplicates them before each next
wave. This keeps output deterministic while allowing all workers to contribute.

Successful recognition prints `ACCEPT tokens=N`; `--stats` appends worker,
round, and task counters. A valid grammar that does not recognize the full input
prints `REJECT` with byte location and expected terminals. Bad CLI input,
grammar, undefined symbols, left recursion, and malformed markup print
`GRAMMAR_ERROR` and exit 2. Rejection exits 1.

Run focused regression tests with `make test`.
