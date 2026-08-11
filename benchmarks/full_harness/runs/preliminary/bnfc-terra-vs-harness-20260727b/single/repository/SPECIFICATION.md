# Project: `bnfc`, a tiny BNF grammar compiler and recognizer

Implement a self-contained ISO C11 command-line program that compiles a small
BNF grammar and recognizes a whitespace-separated terminal-token stream.
External parser generators and non-standard libraries are forbidden.

## Required interface

`make clean all` must build `bin/bnfc`.

```text
bin/bnfc --grammar PATH --input "TOKEN TOKEN ..." [--start NAME]
```

The input after `--input` is split on ASCII whitespace.  A zero-length string is
an empty token stream.  Grammar terminals are single-quoted strings, such as
`'id'`, `'+'`, and `'\\''`; support backslash escapes for quote and backslash.
Nonterminals are identifiers beginning with an ASCII letter or underscore and
continuing with letters, digits, or underscores.

On successful recognition, exit 0 and print one line beginning:

```text
ACCEPT start=NAME tokens=N
```

On a syntactically valid grammar with a rejected input, exit 1 and print one
line beginning `REJECT ` that includes a decimal `offset=` and a nonempty
`expected=` field.  On command-line, grammar-lexing, grammar-parsing, undefined
nonterminal, or left-recursion errors, exit 2 and print one line beginning
`GRAMMAR_ERROR ` with a useful detail (line information when applicable).

## Grammar format

Whitespace is insignificant.  `#` begins a comment through the end of its line.
The first directive is `%start NAME`.  Each production has this form:

```text
Name ::= symbol symbol | another-alternative | ;
```

The final empty alternative denotes epsilon.  Each rule name is defined once;
every referenced nonterminal must be defined.  The tool must diagnose direct
and indirect left recursion before attempting recognition rather than recursing
forever or crashing.

Recognition must support alternatives, epsilon, arbitrary right recursion, and
nested nonterminal expansion.  It must consume the entire token stream to
accept.  A correct implementation may use a safe general recognizer rather than
restricting grammars to LL(1), provided it terminates for all grammars it accepts.

## Required engineering properties

- Build with `-std=c11 -Wall -Wextra -Werror -pedantic`.
- Keep implementation code under `src/` and public/internal headers under
  `include/`.
- Add `make test` and focused tests under `tests/`.
- Avoid global mutable parser state; free allocated memory on normal exits.
- Document the grammar subset, algorithm, and exit statuses in `README.md`.

## Required manager work breakdown

For the manager/worker competitor, keep these six plan items distinct and
independently verifiable.  Additional repair items are allowed only when a prior
item fails its acceptance check.

1. Build skeleton, CLI argument validation, and grammar lexer.
2. Grammar AST parser and ownership-safe storage.
3. Grammar validation: start symbol, duplicate/undefined names, and left recursion.
4. Token-stream recognition with alternatives, epsilon, and full consumption.
5. User-facing acceptance/rejection/error diagnostics and exit statuses.
6. Strict build flags, regression tests, README, and full integration validation.

## Acceptance examples

This arithmetic grammar must accept `id + id * id` and `( id + id ) * id`, and
reject `id + * id`:

```text
%start Expr
Expr ::= Term ExprTail ;
ExprTail ::= '+' Term ExprTail | '-' Term ExprTail | ;
Term ::= Factor TermTail ;
TermTail ::= '*' Factor TermTail | '/' Factor TermTail | ;
Factor ::= 'id' | '(' Expr ')' ;
```

This grammar must accept both the empty stream and `a a a`:

```text
%start S
S ::= 'a' S | ;
```

An undefined nonterminal and direct or indirect left recursion must produce a
`GRAMMAR_ERROR` result with exit status 2.
