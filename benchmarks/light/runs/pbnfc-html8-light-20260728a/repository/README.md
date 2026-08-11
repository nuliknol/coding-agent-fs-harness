# pbnfc

`pbnfc` compiles a small BNF grammar and recognizes a compact HTML-like token
stream:

```sh
make clean all
bin/pbnfc --grammar grammar.bnf --input document.html [--start Rule] [--stats]
```

## Grammar syntax

The first directive is required and selects the default start rule. Token-kind
declarations are optional, but a `$` reference must name a declared kind.
Whitespace and `#` comments are ignored.

```bnf
%start Document
%token IDENT
%token STRING
%token TEXT

Document ::= Nodes ;
Nodes ::= Node Nodes | ;
Node ::= '<' 'p' '>' $TEXT '<' '/' 'p' '>' ;
```

Rules use `::=`, alternatives use `|`, and `;` terminates a rule. An empty
alternative is epsilon. Bare names reference nonterminals, single-quoted
strings match exact token lexemes, and `$IDENT`, `$STRING`, and `$TEXT` match
token kinds. Grammar terminals accept `\'` and `\\` escapes. Duplicate rules,
undefined names, undeclared token references, and direct or indirect
left-recursion are grammar errors. `--start` selects another defined rule.

## Markup tokenization

The lexer emits `<`, `>`, `/`, and `=` inside tags as exact lexemes. Tag names
and attribute names use `[A-Za-z_:][A-Za-z0-9_.:-]*` and have kind `IDENT`.
Single- and double-quoted attribute values have kind `STRING`; quote and
backslash escapes are decoded. Outside tags, the run between successive `<`
delimiters is one `TEXT` token when it contains any non-whitespace byte; its
embedded and edge ASCII whitespace is preserved, while an all-whitespace run
is omitted. Every token stores byte offset, line, and column. Invalid
bytes, unterminated tags, and unterminated or malformed strings are reported
as `GRAMMAR_ERROR` diagnostics.

## Recognition and parallel merge

Recognition is a general Earley-style chart algorithm. Each chart item is
`(rule, alternative, dot, origin)`, so epsilon, right recursion, nesting, and
ambiguity terminate through item deduplication. The complete stream must be
consumed. A persistent pool of exactly eight pthread workers handles every
closure wave and scan. Workers read the grammar and the coordinator's current
chart snapshot and append only to their own candidate vector. The coordinator
waits for all workers, sorts candidates by item fields, then merges and
deduplicates them before another wave. This makes output and statistics
repeatable while keeping scheduling out of the observable result.

The prototype keeps chart vectors in memory for one input and does not build a
parse tree or preserve semantic actions.

## Outputs and statuses

Success prints `ACCEPT tokens=N`. With `--stats`, it also prints
`workers=8 active_workers=8 rounds=N tasks=N,N,N,N,N,N,N,N`; all workers have
positive counts for workers that received nonempty chart intervals. A valid grammar with a
nonmatching token stream prints `REJECT offset=... line=... column=...
expected=...` and exits 1. CLI, grammar, markup-lexing, validation, and
resource failures print one `GRAMMAR_ERROR` line and exit 2.
Expected literal terminals escape newlines, tabs, carriage returns, and other
control bytes so rejection diagnostics always remain one line.
Command-line paths and start-rule overrides use the same escaped rendering in
`GRAMMAR_ERROR` diagnostics.

## Example

The acceptance grammar in `SPECIFICATION.md` recognizes nested elements such
as `<div id="root"><p>Hello <strong>world</strong></p></div>`. The supplied
focused smoke test uses the same mechanisms with a smaller grammar:

```sh
make test
```
