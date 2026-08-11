#!/bin/sh
set -eu
work=tests/.tmp
mkdir -p "$work"
trap 'rm -rf "$work"' EXIT
cat > "$work/arithmetic.bnf" <<'EOF'
%start Expr
Expr ::= Term ExprTail ;
ExprTail ::= '+' Term ExprTail | '-' Term ExprTail | ;
Term ::= Factor TermTail ;
TermTail ::= '*' Factor TermTail | '/' Factor TermTail | ;
Factor ::= 'id' | '(' Expr ')' ;
EOF
bin/bnfc --grammar "$work/arithmetic.bnf" --input 'id + id * id' | grep '^ACCEPT start=Expr tokens=5$'
bin/bnfc --grammar "$work/arithmetic.bnf" --input '( id + id ) * id' | grep '^ACCEPT start=Expr tokens=7$'
if bin/bnfc --grammar "$work/arithmetic.bnf" --input 'id + * id'; then exit 1; fi
cat > "$work/epsilon.bnf" <<'EOF'
%start S
S ::= 'a' S | ;
EOF
bin/bnfc --grammar "$work/epsilon.bnf" --input '' | grep '^ACCEPT start=S tokens=0$'
bin/bnfc --grammar "$work/epsilon.bnf" --input 'a a a' | grep '^ACCEPT start=S tokens=3$'
cat > "$work/left.bnf" <<'EOF'
%start A
A ::= B 'x' ;
B ::= A | 'y' ;
EOF
if bin/bnfc --grammar "$work/left.bnf" --input y; then exit 1; fi
