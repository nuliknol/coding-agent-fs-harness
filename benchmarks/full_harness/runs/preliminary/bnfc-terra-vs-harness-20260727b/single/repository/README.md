# bnfc

`bnfc` recognizes a whitespace-separated terminal-token stream using a small
BNF grammar:

```sh
bin/bnfc --grammar grammar.bnf --input "id + id" [--start Name]
```

The grammar starts with `%start Name`. Rules have the form
`Name ::= symbols | alternative | ;`; a final empty alternative is epsilon.
Terminals are single quoted and support `\\` and `\'`; identifiers use ASCII
letters or `_` first, then letters, digits, or `_`. Whitespace and `#` comments
are ignored.

The program rejects duplicate or undefined names and direct/indirect left
recursion (including nullable prefixes). Recognition uses a finite fixed-point
chart, supporting alternatives, epsilon, nested rules, and right recursion.

Status 0 prints `ACCEPT`, status 1 prints `REJECT offset=... expected=...`, and
status 2 prints `GRAMMAR_ERROR`. Build with `make clean all`; run `make test`.
