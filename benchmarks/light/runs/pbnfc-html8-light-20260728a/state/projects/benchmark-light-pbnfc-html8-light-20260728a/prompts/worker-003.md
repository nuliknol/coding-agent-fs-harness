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

1. `ADD-004` — Closure rounds reprocess the whole chart instead of the required unprocessed snapshot range.

   - `Specification:` “For each chart position and fixed-point closure wave: The coordinator snapshots the current unprocessed item range and partitions it across all eight workers.”
   - `Evidence:` In `recognize()` at [src/recognizer.c:280](/var/home/mf/coding-agent-fs-harness/benchmark/light/runs/pbnfc-html8-light-20260728a/repository/src/recognizer.c:280), `processed` is maintained but never supplied to the pool. Each closure call at [src/recognizer.c:290](/var/home/mf/coding-agent-fs-harness/benchmark/light/runs/pbnfc-html8-light-20260728a/repository/src/recognizer.c:290) dispatches `snapshot`, causing `closure_task()` to revisit indices `0..snapshot-1` every wave rather than only `processed..snapshot-1`.
   - `Required correction:` Dispatch precisely the newly appended interval for each closure wave, while retaining the existing deterministic candidate merge/deduplication behavior. Derive worker task statistics from actual nonempty assigned work rather than copying the global pool generation to every worker.
   - `Verification:` Run an epsilon/right-recursive grammar with `--stats` under an instrumented or focused regression check showing each chart item is processed once per closure wave, and run the supplied stress document confirming all eight workers have positive actual task counts.

Build and supplied checks currently pass: `make clean all`, `make test`, and `../grader.sh "$PWD"` (12/12).