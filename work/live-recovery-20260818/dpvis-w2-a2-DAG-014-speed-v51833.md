# Token usage anomaly resolution

Harness-Fix-Commit: 0f87b0a
Partial-Edit-Disposition: PRESERVE

## Cause

The revision-122 manager replan reached item 9 of an 8-item budget while
correcting guessed test context. It first proposed a directory, then a
nonexistent fixture path, and only a later bounded CMake read identified
`tests/render_compile/render_compile_tests.hip`. The episode changed only its
temporary candidate and published no source mutation.

## Corrective action

Harness 5.18.33 installs deterministic build/test-owner queries, exact named
target and test context admission, manager-free Context Closure grafts, and
bounded manager event batching. These paths supply the registered fixture seam
without consuming a sequence of manager correction actions. All token and
item-start investigation fuses remain unchanged.

## Safe continuation boundary

Preserve the repository, every accepted checkpoint, the raw token ledger, and
the pending DAG-014 replan. Rotate the amplified worker/goal thread as the
resolver requires, discard no source, and resume only the existing first-unmet
criterion under its unchanged DAG and mutation authority.
