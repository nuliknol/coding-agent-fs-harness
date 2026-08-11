# Task Result

Task-ID: 009-hierarchical-markup-revision-01
Status: COMPLETED
Goal-ID: p009.goal.hierarchical-rejection-diagnostics
Goal-Outcome: COMPLETE

## Summary

Completed the public hierarchical-markup rejection-diagnostics boundary from the 33% checkpoint. Added focused CLI coverage for mismatched and unknown hierarchical tags and wired it into the Makefile.

## Modified files

- `Makefile` — added `test-hierarchical-rejection-core` and its smoke binary rule.
- `tests/hierarchical_rejection_smoke.c` — added two public CLI rejection cases and strict diagnostic/status assertions.

## Implemented behavior

The existing public `main` and parallel recognizer diagnostic path was exercised without source changes. The new smoke verifies that a mismatched closing tag and an unknown opening tag each produce exactly one `REJECT` line, with decimal `offset`, `line`, `column`, and nonempty `expected` fields, and exit status 1.

## Validation performed

- `make test-hierarchical-rejection-core` — PASS after initial integration.
- `make test-hierarchical-rejection-core` — PASS after fixture-writer robustness correction; strict C11, warnings-as-errors, and pthread flags were used.
- Mismatched case verified `offset=8 line=2 column=3`.
- Unknown-tag case verified `offset=1 line=1 column=2`.
- Acceptance checkpoint was preserved; no acceptance source or fixture was changed.

Starting progress was 33%. This advances `p009.hierarchical-rejection-diagnostics`; stress/repetition remains outside this leaf.

## Deviations from assignment

None.

## Remaining concerns

The separate hierarchical stress/repeatability criterion remains unverified as required by the bounded assignment.

## Worker assessment

The leaf success evidence passes: public mismatched and unknown hierarchical markup is rejected with exit status 1 and one complete, coordinate-bearing diagnostic line. The goal is complete.
