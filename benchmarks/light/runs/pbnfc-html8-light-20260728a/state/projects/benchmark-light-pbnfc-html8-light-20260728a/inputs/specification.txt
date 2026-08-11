# Project: `pbnfc`, an eight-thread BNF compiler and markup recognizer

Implement a self-contained ISO C11 command-line program that compiles a BNF
grammar and recognizes hierarchical HTML-like documents. The recognizer must
perform its parsing work through a persistent pool of exactly eight POSIX worker
threads and deterministically combine their partial results. External parser
generators and non-standard libraries are forbidden; POSIX `pthread` is allowed.

This is not a file-splitting exercise. All eight workers cooperate on the chart
for one document. A coordinator distributes chart items in parallel rounds,
workers produce thread-local candidates, and the coordinator merges and
deduplicates those candidates in a stable order before the next round.

## Required interface

`make clean all` must build `bin/pbnfc` with strict warnings and pthread support.

```text
bin/pbnfc --grammar PATH --input PATH [--start NAME] [--stats]
```

On recognition success, exit 0 and print:

```text
ACCEPT tokens=N
```

With `--stats`, append these fields on the same line:

```text
workers=8 active_workers=8 rounds=N tasks=N,N,N,N,N,N,N,N
```

Every task count must be positive for the supplied stress document. `rounds`
must be positive. Without `--stats`, output must be deterministic and contain
no timing or scheduling-dependent values.

For a syntactically valid grammar with rejected markup, exit 1 and print one
line beginning `REJECT ` with decimal byte `offset=`, `line=`, and `column=`
fields plus a nonempty `expected=` field. For command-line, markup-lexing,
grammar-lexing, grammar-parsing, undefined-symbol, or left-recursion errors,
exit 2 and print one line beginning `GRAMMAR_ERROR ` with useful detail.

## Grammar language

Whitespace is insignificant and `#` begins a comment through end of line. The
first directive is `%start NAME`. Zero or more token-kind declarations follow:

```text
%token IDENT
%token STRING
%token TEXT
```

Productions use `::=`, `|`, and `;`:

```text
Name ::= symbol symbol | another-alternative | ;
```

An empty alternative denotes epsilon. A single-quoted terminal matches an exact
markup token lexeme. Support `\\'` and `\\\\` escapes inside grammar terminals.
`$IDENT`, `$STRING`, and `$TEXT` match the declared markup token kind regardless
of lexeme. Bare identifiers are nonterminal references. Each rule name is
defined once and every nonterminal and `$TOKEN` reference must be defined.

Detect direct and indirect left recursion before recognition. Right recursion,
epsilon, nested expansion, and ambiguous alternatives must terminate safely.
The engine must consume the entire markup token stream to accept. Do not
hard-code the acceptance examples or tag hierarchy in C; they come from the
compiled grammar.

## Built-in markup lexer

Tokenize compact markup without requiring whitespace between punctuation:

- Inside `<...>`, recognize `<`, `>`, `/`, and `=` as exact literal lexemes.
- Recognize identifiers using `[A-Za-z_:][A-Za-z0-9_.:-]*`; their kind is
  `IDENT`, while exact terminals such as `'a'` may also match their lexeme.
- Recognize both single- and double-quoted attribute values as kind `STRING`,
  with backslash escapes for a quote and backslash.
- Outside tags, each nonempty maximal text run is one `TEXT` token. Preserve its
  byte location while ignoring runs that contain only ASCII whitespace.
- Reject unterminated tags, quoted values, and invalid bytes with accurate
  byte, line, and column diagnostics.

The required grammar must be able to recognize compact nested markup such as:

```html
<a href='url'> link text </a>
<div id="root"><p>Hello <strong>world</strong></p><img src='x.png'/></div>
```

Opening and closing tags must match because the grammar defines separate rules
for `a`, `div`, `span`, `p`, `section`, `ul`, `li`, `strong`, and `em`; `img`
is self-closing. Attributes may appear on every tag and use the recursive
attribute productions. Mismatched, unknown, or malformed tags must reject.

## Required eight-thread parser architecture

Use a safe general chart recognizer, such as Earley recognition. Create exactly
eight worker pthreads once per process and reuse them until parsing ends.

For each chart position and fixed-point closure wave:

1. The coordinator snapshots the current unprocessed item range and partitions
   it across all eight workers.
2. Workers perform prediction/completion work and write only to their own
   candidate vectors; shared grammar and chart snapshots are read-only.
3. A barrier or condition-variable generation protocol returns control to the
   coordinator.
4. The coordinator stable-sorts or otherwise deterministically orders all
   candidates, merges duplicates, appends new items, and repeats until closure.
5. Scanning work is likewise distributed through the pool, with next-position
   candidates combined deterministically.

All workers must perform real chart work on the stress case. Protect lifecycle
state with mutexes/condition variables or barriers, handle allocation failures,
join all threads on every normal/error exit, and avoid data races. Do not create
a new set of threads for every token or chart item. The coordinator is not one
of the eight reported workers.

## Required engineering properties

- Compile C with `-std=c11 -Wall -Wextra -Werror -pedantic -pthread`.
- Keep implementation under `src/` and headers under `include/`.
- Separate grammar lexer/parser, markup lexer, chart representation, worker
  pool, recognizer, diagnostics, and CLI into understandable modules.
- Add `make test` with focused grammar, markup, rejection, and concurrency tests.
- Avoid global mutable parser state and free allocated memory on normal exits.
- Document grammar syntax, markup tokenization, parallel merge invariants,
  limitations, examples, output, and exit statuses in `README.md`.

## Required manager work breakdown

Keep these ten plan items distinct and independently verifiable. Additional
repair items are allowed only after an item fails its acceptance check.

1. Strict pthread build skeleton, CLI contract, locations, and diagnostics.
2. BNF lexer with directives, token kinds, escapes, alternatives, and epsilon.
3. Grammar AST, ownership-safe storage, symbol resolution, and validation.
4. Markup lexer for compact tags, text, identifiers, and quoted attributes.
5. Sequential chart/item semantics serving as a correctness baseline.
6. Persistent eight-thread pool, generation protocol, and clean shutdown.
7. Parallel prediction/completion rounds with thread-local candidate buffers.
8. Parallel scanning, deterministic merge/deduplication, and worker statistics.
9. Hierarchical HTML grammar integration, rejection diagnostics, and stress cases.
10. Strict full build, regression suite, concurrency checks, README, and final validation.

## Acceptance grammar

The implementation and external grader use this grammar shape (additional
equivalent factoring is allowed in the project's own tests):

```text
%start Document
%token IDENT
%token STRING
%token TEXT
Document ::= Nodes ;
Nodes ::= Node Nodes | ;
Node ::= Text | A | Div | Span | P | Section | Ul | Li | Strong | Em | Img ;
Text ::= $TEXT ;
Attributes ::= Attribute Attributes | ;
Attribute ::= $IDENT '=' $STRING ;
A ::= '<' 'a' Attributes '>' Nodes '<' '/' 'a' '>' ;
Div ::= '<' 'div' Attributes '>' Nodes '<' '/' 'div' '>' ;
Span ::= '<' 'span' Attributes '>' Nodes '<' '/' 'span' '>' ;
P ::= '<' 'p' Attributes '>' Nodes '<' '/' 'p' '>' ;
Section ::= '<' 'section' Attributes '>' Nodes '<' '/' 'section' '>' ;
Ul ::= '<' 'ul' Attributes '>' Nodes '<' '/' 'ul' '>' ;
Li ::= '<' 'li' Attributes '>' Nodes '<' '/' 'li' '>' ;
Strong ::= '<' 'strong' Attributes '>' Nodes '<' '/' 'strong' '>' ;
Em ::= '<' 'em' Attributes '>' Nodes '<' '/' 'em' '>' ;
Img ::= '<' 'img' Attributes '/' '>' ;
```
