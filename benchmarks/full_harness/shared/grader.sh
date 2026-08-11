#!/usr/bin/env bash
# External deterministic grader for the parallel BNF/markup benchmark.
set -Eeuo pipefail

[[ $# -eq 1 ]] || { printf 'Usage: %s REPOSITORY\n' "${0##*/}" >&2; exit 2; }
repo="$1"
bin="$repo/bin/pbnfc"
[[ -d "$repo" ]] || { printf 'repository is missing: %s\n' "$repo" >&2; exit 2; }

work="$(mktemp -d "${TMPDIR:-/tmp}/pbnfc-grader.XXXXXX")"
trap 'rm -rf "$work"' EXIT
pass=0
total=12

run_case()
{
	local name="$1" expected="$2" pattern="$3"
	shift 3
	local output status
	set +e
	output="$("$@" 2>&1)"
	status=$?
	set -e
	if [[ "$status" == "$expected" ]] && grep -Eq "$pattern" <<<"$output"; then
		printf 'PASS %s\n' "$name"
		pass=$((pass + 1))
	else
		printf 'FAIL %s status=%s expected=%s output=%q\n' "$name" "$status" "$expected" "$output"
	fi
}

cat > "$work/html.bnf" <<'EOF'
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
EOF
cat > "$work/undefined.bnf" <<'EOF'
%start S
%token TEXT
S ::= Missing ;
EOF
cat > "$work/left-recursive.bnf" <<'EOF'
%start S
%token TEXT
S ::= A ;
A ::= S | $TEXT ;
EOF
printf "%s\n" "<a href='url'> link text </a>" > "$work/link.html"
printf '%s\n' '<div id="root" class='"'"'main'"'"'><p>Hello <strong>world</strong></p><img src='"'"'x.png'"'"'/></div>' > "$work/nested.html"
printf '%s\n' '<div><a href='"'"'x'"'"'>broken</div></a>' > "$work/mismatch.html"
printf '%s\n' '<a href=url>broken</a>' > "$work/unquoted.html"
printf '%s\n' '<table><p>unknown</p></table>' > "$work/unknown.html"

{
	for _ in $(seq 1 24); do printf '<section>'; done
	printf '<div><p>deep <em>hierarchy</em></p></div>'
	for _ in $(seq 1 24); do printf '</section>'; done
	printf '\n'
} > "$work/deep.html"

{
	for i in $(seq 1 96); do
		printf "<section id='s%s'><div class='card'><p>item %s <strong>bold</strong></p><ul><li>one</li><li><a href='u%s'><span>link</span></a></li></ul><img src='p%s.png'/></div></section>" "$i" "$i" "$i" "$i"
	done
	printf '\n'
} > "$work/stress.html"

if make -C "$repo" clean all >/dev/null 2>&1 && [[ -x "$bin" ]] &&
	command -v nm >/dev/null 2>&1 && nm -u "$bin" 2>/dev/null | grep -q 'pthread_create'; then
	printf 'PASS strict-pthread-build\n'
	pass=$((pass + 1))
else
	printf 'FAIL strict-pthread-build\n'
fi

if [[ -x "$bin" ]]; then
	run_case requested-link 0 '^ACCEPT tokens=[0-9]+$' "$bin" --grammar "$work/html.bnf" --input "$work/link.html"
	run_case nested-attributes 0 '^ACCEPT tokens=[0-9]+$' "$bin" --grammar "$work/html.bnf" --input "$work/nested.html"
	run_case deep-hierarchy 0 '^ACCEPT tokens=[0-9]+$' "$bin" --grammar "$work/html.bnf" --input "$work/deep.html"
	run_case mismatched-tags 1 '^REJECT offset=[0-9]+ line=[0-9]+ column=[0-9]+ expected=.+$' "$bin" --grammar "$work/html.bnf" --input "$work/mismatch.html"
	run_case unquoted-attribute 1 '^REJECT offset=[0-9]+ line=[0-9]+ column=[0-9]+ expected=.+$' "$bin" --grammar "$work/html.bnf" --input "$work/unquoted.html"
	run_case unknown-tag 1 '^REJECT offset=[0-9]+ line=[0-9]+ column=[0-9]+ expected=.+$' "$bin" --grammar "$work/html.bnf" --input "$work/unknown.html"
	run_case undefined-symbol 2 '^GRAMMAR_ERROR .+$' "$bin" --grammar "$work/undefined.bnf" --input "$work/link.html"
	run_case indirect-left-recursion 2 '^GRAMMAR_ERROR .+$' "$bin" --grammar "$work/left-recursive.bnf" --input "$work/link.html"

	stats="$($bin --grammar "$work/html.bnf" --input "$work/stress.html" --stats 2>&1 || true)"
	if grep -Eq '^ACCEPT tokens=[0-9]+ workers=8 active_workers=8 rounds=[1-9][0-9]* tasks=([1-9][0-9]*,){7}[1-9][0-9]*$' <<<"$stats"; then
		printf 'PASS eight-worker-stress\n'
		pass=$((pass + 1))
	else
		printf 'FAIL eight-worker-stress output=%q\n' "$stats"
	fi

	first="$($bin --grammar "$work/html.bnf" --input "$work/stress.html" 2>&1 || true)"
	deterministic=1
	for _ in $(seq 1 5); do
		current="$($bin --grammar "$work/html.bnf" --input "$work/stress.html" 2>&1 || true)"
		[[ "$current" == "$first" ]] || deterministic=0
	done
	if (( deterministic == 1 )) && grep -Eq '^ACCEPT tokens=[0-9]+$' <<<"$first"; then
		printf 'PASS deterministic-merge\n'
		pass=$((pass + 1))
	else
		printf 'FAIL deterministic-merge first=%q\n' "$first"
	fi

	if make -C "$repo" test >/dev/null 2>&1; then
		printf 'PASS project-tests\n'
		pass=$((pass + 1))
	else
		printf 'FAIL project-tests\n'
	fi
else
	printf 'SKIP functional checks: bin/pbnfc is absent\n'
fi

printf 'SCORE %s/%s\n' "$pass" "$total"
[[ "$pass" == "$total" ]]
