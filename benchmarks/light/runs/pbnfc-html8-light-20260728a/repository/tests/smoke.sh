#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
output=$("$root/bin/pbnfc" --grammar "$root/tests/smoke.grammar" --input "$root/tests/smoke.input" --stats)
case "$output" in
  ACCEPT\ tokens=*\ workers=8\ active_workers=8\ rounds=*\ tasks=*,*,*,*,*,*,*,*) : ;;
  *) echo "unexpected smoke output: $output" >&2; exit 1 ;;
esac

set +e
reject=$("$root/bin/pbnfc" --grammar "$root/tests/smoke.grammar" --input "$root/tests/smoke.input" --start Img)
code=$?
set -e
[ "$code" -eq 1 ]
case "$reject" in
  REJECT\ offset=*\ line=*\ column=*\ expected=*) : ;;
  *) echo "unexpected rejection output: $reject" >&2; exit 1 ;;
esac

set +e
punctuation=$("$root/bin/pbnfc" --grammar "$root/tests/ident.grammar" --input "$root/tests/ident.input")
punctuation_code=$?
set -e
[ "$punctuation_code" -eq 1 ]
case "$punctuation" in
  REJECT\ offset=*\ line=*\ column=*\ expected=*) : ;;
  *) echo "punctuation was treated as IDENT: $punctuation" >&2; exit 1 ;;
esac

epsilon=$("$root/bin/pbnfc" --grammar "$root/tests/epsilon.grammar" --input "$root/tests/epsilon.input" --stats)
case "$epsilon" in
  ACCEPT\ tokens=0\ workers=8\ active_workers=8\ rounds=*\ tasks=*,*,*,*,*,*,*,*) : ;;
  *) echo "epsilon grammar was rejected: $epsilon" >&2; exit 1 ;;
esac

empty_string=$("$root/bin/pbnfc" --grammar "$root/tests/empty-string.grammar" --input "$root/tests/empty-string.input")
case "$empty_string" in
  ACCEPT\ tokens=6) : ;;
  *) echo "empty markup string was not matched: $empty_string" >&2; exit 1 ;;
esac

set +e
newline_terminal=$("$root/bin/pbnfc" --grammar "$root/tests/newline-terminal.grammar" --input "$root/tests/epsilon.input")
newline_code=$?
set -e
[ "$newline_code" -eq 1 ]
[ "$(printf '%s\n' "$newline_terminal" | wc -l | tr -d ' ')" -eq 1 ]
case "$newline_terminal" in
  REJECT\ offset=*\ line=*\ column=*\ expected=*\\n*) : ;;
  *) echo "newline expectation was not escaped: $newline_terminal" >&2; exit 1 ;;
esac

set +e
bad_path=$("$root/bin/pbnfc" --grammar "$(printf 'missing\npath')" --input "$root/tests/epsilon.input")
bad_path_code=$?
bad_start=$("$root/bin/pbnfc" --grammar "$root/tests/smoke.grammar" --input "$root/tests/smoke.input" \
  --start "$(printf 'unknown\nname')")
bad_start_code=$?
set -e
[ "$bad_path_code" -eq 2 ]
[ "$bad_start_code" -eq 2 ]
[ "$(printf '%s\n' "$bad_path" | wc -l | tr -d ' ')" -eq 1 ]
[ "$(printf '%s\n' "$bad_start" | wc -l | tr -d ' ')" -eq 1 ]
case "$bad_path" in
  GRAMMAR_ERROR\ *) : ;;
  *) echo "path diagnostic was not escaped: $bad_path" >&2; exit 1 ;;
esac
case "$bad_start" in
  GRAMMAR_ERROR\ *) : ;;
  *) echo "start diagnostic was not escaped: $bad_start" >&2; exit 1 ;;
esac
