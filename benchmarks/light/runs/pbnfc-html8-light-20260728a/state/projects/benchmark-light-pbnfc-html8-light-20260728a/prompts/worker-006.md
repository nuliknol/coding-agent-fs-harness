# Persistent goal remediation

Resume the same persistent project goal. The Terra manager rejected completion
and produced the attached completion addendum.

Treat every `ADD-NNN` finding as required work, but keep the immutable original
specification authoritative. Inspect the evidence yourself, then implement all
valid corrections in one coherent pass. Refactor architectural or design
problems when the addendum shows they prevent correct specification behavior.
Do not patch only the visible symptom if the underlying design would leave the
feature incomplete.

After resolving the entire addendum, re-read the complete specification and
look for connected omissions that the manager did not explicitly list. Build,
run the allowed smoke test, and add at most one focused regression test for a
bug you fixed. Continue autonomously until maximum honest completion is reached.

Do not stop after describing a plan or fixing only the first finding. Do not
modify harness state, immutable inputs, or review/addendum files. Follow the
prototype/feature-first development policy; do not expand the task into
production hardening or a large testing project.

# Harness context

Project: `benchmark-light-pbnfc-html8-light-20260728a`

Repository: `/var/home/mf/coding-agent-fs-harness/benchmark/light/runs/pbnfc-html8-light-20260728a/repository`

Immutable specification: `/var/home/mf/coding-agent-fs-harness/benchmark/light/runs/pbnfc-html8-light-20260728a/state/projects/benchmark-light-pbnfc-html8-light-20260728a/inputs/specification.txt`

Development policy: `/var/home/mf/coding-agent-fs-harness/benchmark/light/runs/pbnfc-html8-light-20260728a/state/projects/benchmark-light-pbnfc-html8-light-20260728a/inputs/development-policy.txt`


Manager-authored persistent goal: `/var/home/mf/coding-agent-fs-harness/benchmark/light/runs/pbnfc-html8-light-20260728a/state/projects/benchmark-light-pbnfc-html8-light-20260728a/control/worker-goal.md`

# Completion addendum to resolve

DECISION: REVISE

1. `ADD-008` — Some command-line failures violate the required one-line `GRAMMAR_ERROR` contract.

   - `Specification:` “For command-line … errors, exit 2 and print one line beginning `GRAMMAR_ERROR ` with useful detail.”
   - `Evidence:` `src/main.c` prints unreadable grammar/input paths verbatim; `src/grammar.c:542` includes an undefined `--start` value verbatim. Passing a newline-bearing path or start name produces two output lines, e.g. `bin/pbnfc --grammar $'missing\npath' ...` exits 2 with `GRAMMAR_ERROR cannot read grammar: missing\npath`.
   - `Required correction:` Escape or safely render command-supplied paths and start names so every error path emits exactly one `GRAMMAR_ERROR` line.
   - `Verification:` Run with `--grammar $'missing\npath'` and with `--start $'unknown\nname'`; each must exit 2 and produce exactly one line beginning `GRAMMAR_ERROR `.

Build, project tests, and external grading otherwise pass: `make clean all`, `make test`, and `../grader.sh "$PWD"` (12/12).