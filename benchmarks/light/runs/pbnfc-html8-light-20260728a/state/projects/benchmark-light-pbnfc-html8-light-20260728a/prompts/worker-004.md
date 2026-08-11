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

1. `ADD-005` — The chart closure misses already-completed epsilon constituents.

   - `Specification:` “Right recursion, epsilon, nested expansion, and ambiguous alternatives must terminate safely,” and the engine must recognize the compiled grammar’s full language.
   - `Evidence:` `closure_task()` in `src/recognizer.c` predicts a nonterminal but does not advance that newly added caller against an already-completed same-position item. The valid, acyclic epsilon grammar `S ::= X B A; X ::= A C; A ::=; B ::=; C ::=;` rejects an empty input: exit `1`, `REJECT offset=0 line=1 column=1 expected=markup token`; it must accept.
   - `Required correction:` Restore complete Earley closure semantics while retaining deterministic worker merges: when an item expecting a nonterminal is added and that nonterminal is already complete at the chart position, emit the advanced item (or implement an equivalent correct agenda invariant).
   - `Verification:` Run the grammar above against an empty input; it exits `0` with `ACCEPT tokens=0`.

`make clean all`, `make test`, and `../grader.sh "$PWD"` pass (12/12), but they do not cover this required epsilon/nested-expansion case.