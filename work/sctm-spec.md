# Source Code Transaction Manager — Short Specification

## 1. Purpose

SCTM is the **single authoritative writer** to a harness project's source repository.

Parallel coding agents must not directly modify the canonical working tree. They operate on source snapshots/context and submit proposed filesystem changes to SCTM as transactions.

```text
Worker 1 ──┐
Worker 2 ──┤
Worker 3 ──┼── patches ──> SCTM ──> canonical repository
Worker 4 ──┘
```

SCTM serializes mutations while allowing reasoning and patch production to remain parallel.

Core invariant:

[
\boxed{\text{Only SCTM modifies canonical project files.}}
]

It applies to **all repository files**, not source-language-specific files:

```text
.c
.cpp
.h
.py
.sh
.md
.json
.yaml
Makefile
CMakeLists.txt
tests
assets
generated metadata
...
```

including file creation, modification, deletion, rename, and—where Git supports the transaction representation—binary changes.

---

## 2. Transaction input

Each submitted transaction contains at minimum:

```text
transaction_id
project_id
worker_id
task_id

base_commit
patch_file

declared_paths
optional declared_symbols
```

Recommended additional fields:

```text
assignment_id
capability_id
base_file_hashes
description
```

The patch should use standard Git patch representation.

Example conceptual request:

```text
transaction_id=TX-1082
worker_id=W3
task_id=DAG-0042
base_commit=abc123
patch=/transactions/TX-1082/change.patch
declared_paths=src/foo.c,tests/foo_test.c
```

---

# 3. Transaction processing

SCTM processes transactions **one at a time** under an exclusive repository lock.

For transaction (T):

```text
RECEIVE
  ↓
VALIDATE REQUEST
  ↓
CHECK AUTHORITY
  ↓
CHECK BASE STATE
  ↓
CHECK PATCH APPLICABILITY
  ↓
APPLY
  ↓
VERIFY RESULT
  ↓
COMMIT
  ↓
RESPOND
```

A transaction must either:

[
\boxed{\text{commit completely}}
]

or:

[
\boxed{\text{leave canonical state unchanged}.}
]

No partial application is permitted.

---

# 4. Required validation

Before mutation, SCTM verifies:

### Request validity

Required metadata exists and transaction ID has not already been processed.

### Capability/scope

Every changed path is authorized by the worker assignment.

A patch touching undeclared paths is rejected.

### Baseline

Compare the transaction's expected base with current repository state.

A changed repository does **not automatically cause rejection**.

SCTM should attempt to determine whether the patch can still apply safely.

### Patch applicability

Conceptually:

```text
git apply --check ...
```

followed by the controlled application strategy.

If the changed regions remain compatible, apply it.

If not, return a conflict.

---

# 5. Successful response

Example:

```text
status=APPLIED
transaction_id=TX-1082
commit=def456
previous_commit=abc999
changed_paths=src/foo.c,tests/foo_test.c
```

The worker does not need to resume merely because another worker modified an unrelated part of the same file.

---

# 6. Conflict response

If the transaction cannot safely apply:

```text
status=CONFLICT
transaction_id=TX-1082
reason=PATCH_CONTEXT_CHANGED
file=src/foo.c
base_hash=...
current_hash=...
```

Also provide the **smallest useful current-state delta** necessary for the worker to repair its patch.

For example:

```text
conflicting_region:
    src/foo.c:410-450

delta_since_worker_base:
    ...
```

Then:

```text
SCTM → supervisor
          ↓
codex exec resume <worker-session>
          ↓
worker updates local understanding
          ↓
worker submits TX-1083
```

The agent should not reread the whole repository.

---

# 7. Result statuses

Keep v1 small:

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

Do **not** ask an LLM to classify these.

They are deterministic transaction outcomes.

---

# 8. Concurrency model

Multiple workers may simultaneously produce modifications:

[
W_1,W_2,\ldots,W_N.
]

SCTM maintains a transaction queue:

```text
TX1
TX2
TX3
TX4
...
```

but has exactly:

[
\boxed{1\text{ canonical writer}}
]

Initially use FIFO.

This gives you:

[
\boxed{\text{parallel computation + serialized commits}}
]

without repository corruption.

---

# 9. Same-file parallelism must be allowed

This is an essential requirement.

Suppose:

```text
worker A → foo.c::parse()
worker B → foo.c::encode()
```

Both start from commit (C_0).

A commits:

[
C_0\xrightarrow{P_A}C_1.
]

When (P_B) arrives, SCTM must **not reject it simply because `foo.c` changed**.

It should attempt:

[
P_B(C_1).
]

If it applies cleanly:

[
C_1\xrightarrow{P_B}C_2.
]

Only genuine conflicting changes should require worker intervention.

This is what lets you remove file-level serialization from your DAG.

---

# 10. Durable transaction ledger

Every request and response should be permanently recorded:

```text
transactions/
    TX-1082/
        request
        patch
        result
        stdout
        stderr
        base-state
        resulting-commit
```

This provides:

* crash recovery,
* debugging,
* performance statistics,
* conflict statistics,
* worker attribution,
* decomposition analysis.

A transaction ID must be **idempotent**:

[
submit(TX42),submit(TX42)
]

must never apply the patch twice.

---

# 11. Crash safety

SCTM must use an exclusive Linux lock, e.g. conceptually:

```text
flock
```

and transaction staging.

Required invariant:

> A process crash at any stage must leave either the old canonical state or the completely committed new state.

On startup SCTM should detect abandoned/incomplete transaction directories and recover deterministically.

---

# 12. Integration with ACP

ACP handles semantic authority:

```text
Worker → NEED_SCOPE(X) → Manager
Manager → GRANT_SCOPE(X)
```

SCTM enforces the resulting capability mechanically.

So:

```text
Project Manager
      │
      │ authority
      ▼
Worker
      │
      │ proposed patch
      ▼
SCTM
      │
      │ mechanically verifies authority
      ▼
Repository
```

SCTM must **never make architectural or product decisions**.

When an operation is semantically questionable but mechanically legal, it reports the condition upward rather than inventing a decision.

---

# 13. What SCTM should NOT do

Initially, do not make it responsible for:

* decomposition,
* project scheduling,
* deciding architecture,
* resolving specification ambiguity,
* judging whether a worker's design is good,
* LLM-based merge conflict resolution.

Its responsibility is much narrower:

[
\boxed{
\text{validate}
+
\text{serialize}
+
\text{apply}
+
\text{commit}
+
\text{report}
}
]

Keep that boundary hard.

---

# Bash is a very reasonable implementation

For v1 I would absolutely use Bash.

You already have all the difficult primitives:

```text
flock
git diff
git apply
git status
git rev-parse
git hash-object
git diff-tree
git commit
sha256sum
mktemp
mv
fsync-capable helpers where necessary
```

So the Bash daemon is primarily a state machine around Git:

```text
while running
do
	find next transaction
	lock repository
	validate
	stage
	apply
	commit or rollback
	write result atomically
	unlock
done
```

That's very appropriate for your current harness architecture.

I would **not rewrite this in C yet**. First establish the protocol and discover what the real requirements are. If SCTM eventually processes hundreds or thousands of transactions per second, needs an in-memory dependency graph, sophisticated AST-aware merging, or becomes a reliability-critical standalone service, then a C implementation could make sense.

But your present scale will be dominated by:

[
\text{LLM inference}+\text{build/test time}
]

rather than a few milliseconds of Bash orchestration.

So:

[
\boxed{\text{Bash + Git + flock is the right v1.}}
]

The most important design decision isn't the language. It's making **SCTM the only canonical writer** while allowing any number of agents to concurrently compute patches against versioned source state.

