# Source Code Transaction Manager v1

SCTM is the single canonical repository writer for isolated harness workers.
Workers reason and edit concurrently in detached Git worktrees, but submit
immutable transactions instead of modifying the canonical worktree.

## Request

Every request records a unique `transaction_id`, project, worker, task, full
base commit, standard binary-capable Git patch, exact declared path set, ACP
capability path set, commit message, and focused validation command. An ID is
idempotent: a repeated byte-identical request returns the first durable result;
reuse with different input is rejected.

## Processing

The daemon owns a per-project FIFO queue and takes one exclusive repository
`flock` per transaction. It verifies the request and base, creates a detached
staging worktree at the current canonical HEAD, attempts `git apply --3way
--index`, compares the resulting no-rename path set exactly with the declaration,
and checks every path against the ACP capability. It then commits and validates
the complete candidate in staging before fast-forwarding the canonical tree.

The transaction is all-or-nothing. A different current HEAD is not itself a
conflict: compatible edits, including disjoint changes in one file, apply. A
genuine patch-context collision produces a bounded delta from the worker base
and does not mutate canonical source.

Terminal statuses are:

```text
APPLIED
CONFLICT
STALE_BASE
SCOPE_VIOLATION
INVALID_PATCH
INVALID_REQUEST
VALIDATION_FAILED
INTERNAL_ERROR
```

These are deterministic outcomes; SCTM never makes architecture, product, or
decomposition decisions.

## Durability and recovery

The ledger lives at:

```text
$HARNESS_ROOT/projects/$PROJECT/control/sctm/transactions/$TRANSACTION_ID/
```

It retains the immutable request, patch, declared/capability paths, base state,
stdout/stderr, validation output, state, result, and resulting commit or conflict
delta. Intake and results are published with atomic renames and filesystem sync
barriers where available.

Before canonical publication the daemon records `COMMITTING` with the previous
and candidate commits. On restart it reconstructs missing queue entries. If
canonical HEAD is still the previous commit it safely retries; if HEAD is the
candidate it restores the complete tree/index and publishes `APPLIED` without
committing twice; any third state becomes `INTERNAL_ERROR`.

Operators use `sctm-daemon-start`, `sctm-daemon-stop`, and `sctm-status` with a
harness environment file. `harness-start` and `harness-stop` manage the daemon
automatically when `HARNESS_SCTM_ENABLED=1`.
