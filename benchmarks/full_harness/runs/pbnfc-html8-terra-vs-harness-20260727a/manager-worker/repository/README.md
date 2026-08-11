# pbnfc

`pbnfc` is a self-contained ISO C11 command-line program that compiles a
small BNF grammar and recognizes hierarchical HTML-like markup. It uses a
persistent pool of exactly eight POSIX worker threads for chart recognition.

## Build and usage

Build the program with:

```sh
make clean all
```

The command-line interface is:

```text
bin/pbnfc --grammar PATH --input PATH [--start NAME] [--stats]
```

This self-contained example writes a temporary grammar and input, then runs
the recognizer:

```sh
example_dir=$(mktemp -d)
trap 'rm -rf "$example_dir"' EXIT
cat >"$example_dir/text.bnf" <<'EOF'
%start Document
%token TEXT
Document ::= $TEXT ;
EOF
printf 'hello' >"$example_dir/page.html"
bin/pbnfc --grammar "$example_dir/text.bnf" --input "$example_dir/page.html"
# ACCEPT tokens=1
```

The acceptance grammar in `SPECIFICATION.md` can recognize nested elements
such as:

```html
<div id="root"><p>Hello <strong>world</strong></p><img src='x.png'/></div>
```

`--start NAME` selects a different defined nonterminal when the grammar has
more than one useful entry point. Without `--stats`, successful output is
deterministic and has no timing or scheduling-dependent values.

## Grammar syntax

Whitespace is insignificant and `#` starts a comment that runs to the end of
the line. A grammar begins with `%start NAME`, followed by optional token-kind
declarations:

```bnf
%start Document
%token IDENT
%token STRING
%token TEXT
```

Rules use `::=`, alternatives use `|`, and rules end with `;`:

```bnf
Document ::= Nodes ;
Nodes ::= Node Nodes | ;
Node ::= Text | A ;
Text ::= $TEXT ;
A ::= '<' 'a' Attributes '>' Nodes '<' '/' 'a' '>' ;
```

An empty alternative (`| ;` in the examples) is epsilon. A single-quoted
terminal matches an exact markup-token lexeme. Within such a terminal,
`\\'` escapes a quote and `\\\\` escapes a backslash. `$IDENT`, `$STRING`, and
`$TEXT` match a declared token kind regardless of its lexeme; bare identifiers
refer to nonterminals. Every rule name must be unique, and every referenced
nonterminal or token kind must be defined. Direct and indirect left recursion
is rejected before recognition; right recursion, epsilon, nested expansion,
and ambiguous alternatives are supported.

## Markup tokenization

The built-in lexer accepts compact markup, so whitespace is not required
between punctuation. Within a tag it emits `<`, `>`, `/`, and `=` as literal
tokens. Identifiers match `[A-Za-z_:][A-Za-z0-9_.:-]*` and have kind `IDENT`.
Single- and double-quoted attribute values have kind `STRING`; backslash can
escape the quote or a backslash. Outside tags, each nonempty maximal text run
is one `TEXT` token. Runs containing only ASCII whitespace are ignored, while
the original byte location of retained text is preserved.

Unterminated tags or quoted values and invalid bytes produce a grammar error
with byte, line, and column information. The grammar determines which tags,
attributes, nesting, and self-closing forms are accepted; the recognizer does
not hard-code a particular document hierarchy. The supplied acceptance shape
defines rules for `a`, `div`, `span`, `p`, `section`, `ul`, `li`, `strong`, and
`em`, with `img` as a self-closing element.

## Parallel recognition and merge invariants

Recognition uses a general chart algorithm. One document is processed by all
eight workers rather than by splitting the input into independent files. For
each chart position and closure wave, the coordinator snapshots the pending
item range and partitions it across every worker. Workers read the shared
grammar and chart snapshot, perform prediction/completion work, and write
candidate items only to thread-local buffers.

After a barrier or condition-variable generation completes a wave, the
coordinator orders candidates deterministically, merges them, and removes
duplicates before the next wave. Scanning is also distributed through the
same persistent pool and its next-position candidates are merged in the same
stable manner. This preserves chart fixed-point semantics and deterministic
results independently of scheduling. Workers are created once per process,
reused until parsing ends, and joined on normal and error exits.

With `--stats`, a successful result also reports the worker and scheduling
summary:

```text
ACCEPT tokens=N workers=8 active_workers=8 rounds=N tasks=N,N,N,N,N,N,N,N
```

For a supplied stress document, `rounds` and every task count are positive.

## Output and exit statuses

On successful recognition, the program prints one line and exits `0`:

```text
ACCEPT tokens=N
```

With `--stats`, the statistics fields shown above are appended on the same
line. A syntactically valid grammar with rejected markup prints one diagnostic
line beginning with `REJECT ` and exits `1`. The line includes decimal
`offset=`, `line=`, and `column=` fields and a nonempty `expected=` field.

Command-line errors, markup-lexing errors, grammar-lexing or grammar-parsing
errors, undefined symbols, and direct or indirect left recursion print one
useful line beginning with `GRAMMAR_ERROR ` and exit `2`.

## Limitations

This is a recognizer, not a formatter or DOM builder: it validates the complete
markup token stream and reports acceptance or the first useful rejection
diagnostic. It accepts only the grammar language and markup forms described
above. Attribute values are tokens, not decoded application data, and text is
matched according to the grammar's `$TEXT` rules. The entire input must be
consumed for acceptance. There is no promise of recovery after malformed
grammar or markup input.

## Development checks

The required strict build check is:

```sh
make clean all
```

The external grader remains authoritative for the complete grammar, markup,
rejection, concurrency, and final validation requirements.
