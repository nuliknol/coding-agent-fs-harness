#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
"$root/bin/pbnfc" --grammar "$root/tests/accept.bnf" --input "$root/tests/valid.html" --stats | grep -E '^ACCEPT tokens=[0-9]+ workers=8 active_workers=8 rounds=[1-9][0-9]* tasks=[1-9][0-9]*,[1-9][0-9]*,[1-9][0-9]*,[1-9][0-9]*,[1-9][0-9]*,[1-9][0-9]*,[1-9][0-9]*,[1-9][0-9]*$'
if "$root/bin/pbnfc" --grammar "$root/tests/accept.bnf" --input "$root/tests/invalid.html" >/dev/null; then exit 1; fi
if "$root/bin/pbnfc" --grammar "$root/tests/left.bnf" --input "$root/tests/valid.html" >/dev/null 2>&1; then exit 1; fi
