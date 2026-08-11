#!/usr/bin/env bash
# External, deterministic functional grader for the bnfc benchmark.
set -Eeuo pipefail

[[ $# -eq 1 ]] || { printf 'Usage: %s REPOSITORY\n' "${0##*/}" >&2; exit 2; }
repo="$1"
bin="$repo/bin/bnfc"
[[ -d "$repo" ]] || { printf 'repository is missing: %s\n' "$repo" >&2; exit 2; }

work="$(mktemp -d "${TMPDIR:-/tmp}/bnfc-grader.XXXXXX")"
trap 'rm -rf "$work"' EXIT
pass=0
total=8

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

cat > "$work/arithmetic.bnf" <<'EOF'
%start Expr
Expr ::= Term ExprTail ;
ExprTail ::= '+' Term ExprTail | '-' Term ExprTail | ;
Term ::= Factor TermTail ;
TermTail ::= '*' Factor TermTail | '/' Factor TermTail | ;
Factor ::= 'id' | '(' Expr ')' ;
EOF
cat > "$work/epsilon.bnf" <<'EOF'
%start S
S ::= 'a' S | ;
EOF
cat > "$work/undefined.bnf" <<'EOF'
%start S
S ::= Missing ;
EOF
cat > "$work/left-recursive.bnf" <<'EOF'
%start S
S ::= A ;
A ::= S 'x' | 'x' ;
EOF

if make -C "$repo" clean all >/dev/null 2>&1 && [[ -x "$bin" ]]; then
	printf 'PASS strict-build\n'
	pass=$((pass + 1))
else
	printf 'FAIL strict-build\n'
fi

if [[ -x "$bin" ]]; then
	run_case arithmetic-precedence 0 '^ACCEPT start=Expr tokens=5$' "$bin" --grammar "$work/arithmetic.bnf" --input 'id + id * id'
	run_case arithmetic-parentheses 0 '^ACCEPT start=Expr tokens=7$' "$bin" --grammar "$work/arithmetic.bnf" --input '( id + id ) * id'
	run_case syntax-rejection 1 '^REJECT offset=[0-9]+ expected=.+$' "$bin" --grammar "$work/arithmetic.bnf" --input 'id + * id'
	run_case epsilon-empty 0 '^ACCEPT start=S tokens=0$' "$bin" --grammar "$work/epsilon.bnf" --input ''
	run_case epsilon-repetition 0 '^ACCEPT start=S tokens=3$' "$bin" --grammar "$work/epsilon.bnf" --input 'a a a'
	run_case undefined-name 2 '^GRAMMAR_ERROR .+$' "$bin" --grammar "$work/undefined.bnf" --input ''
	run_case indirect-left-recursion 2 '^GRAMMAR_ERROR .+$' "$bin" --grammar "$work/left-recursive.bnf" --input x
else
	printf 'SKIP functional checks: bin/bnfc is absent\n'
	# Build is already one failed score; retain the remaining six as failures.
fi

printf 'SCORE %s/%s\n' "$pass" "$total"
[[ "$pass" == "$total" ]]
