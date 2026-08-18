# Agent Coordination Protocol v1

ACP is a durable control-plane protocol. Message bodies never contain source
dumps; bounded evidence is referenced by a content-addressed artifact.

## Request envelope

Every request contains exactly one value for:

```text
ACP-Version: 1
Request-ID: acp-<fingerprint-prefix>-<sequence>
Project: <project>
Task-ID: <immutable task revision>
Thread-ID: <durable provider thread identifier>
Sequence: <positive integer>
Request-Type: CONTEXT|SCOPE|PREREQUISITE|SPLIT|CHALLENGE|CANCEL
Request-Kind: <typed classification>
Identifier: <one exact symbol, path, criterion, or boundary>
Reason: <one bounded sentence>
Workspace-Fingerprint: sha256:<digest>
Request-Fingerprint: sha256:<digest>
Evidence-Artifact: -|<content-addressed path>
Assignment: <immutable assignment path>
Requested-At: <UTC timestamp>
Initial-Scope-Fingerprint: sha256:<digest>
Initial-Context-Fingerprint: sha256:<digest>
Leaf-Type: <bounded decomposition classification>
Planner: <decomposition model identity>
```

`CONTEXT` kinds are:

```text
TYPE_DEFINITION
SYMBOL_DEFINITION
CALLER_CONTRACT
CALLEE_CONTRACT
FAILING_ASSERTION
TEST_TARGET
TEST_OWNER
BUILD_TARGET
BUILD_OWNER
OWNER
PRODUCER
CONSUMER
REPRESENTATION_WRITER
```

## Authority

- A worker authors observations and requests only.
- The deterministic Context Broker may grant bounded read evidence when the
  requested fact is an assignment seed or direct indexed graph neighbor.
- Scope, prerequisite, and split requests always require persistent-manager
  adjudication. No worker message mutates authority or the accepted DAG.
- Sol may judge global architecture/decomposition from compiled evidence; it
  is not an implementation fallback. Luna performs implementation.

## Durable lifecycle

The append-only event sequence is:

```text
REQUESTED -> GRANTED|DENIED|DEFERRED|SUPERSEDED
          -> MANAGER_ACCEPT|MANAGER_CHECKPOINT|MANAGER_REPLAN|MANAGER_BLOCK
          -> GRANT_SCOPE|CREATE_PREREQUISITE|SPLIT_TASK|REPLAN_TASK|DENY_REQUEST
             |CANCEL_TASK|ARCHITECTURE_REASSESSMENT
             |SPECIFICATION_CLARIFICATION
          -> PREREQUISITE_CREATED|SPLIT_CHILD_CREATED -> RESUMED
```

Context grants resume the same durable thread. Structural requests end the
ephemeral inference process and preserve the thread for the next authorized
revision. Discovered prerequisite/split claims and their dispositions append
to `discovered-graph.tsv`; accepted project criteria remain governed by the
existing append-only decomposition publisher.

## Investigation fuses

Duplicate fingerprints, stale workspace/authority, excessive request count,
excessive added evidence, and repeated negotiation without verified gain are
durable anomalies. These complement and never raise or remove the existing
500,000-token authoritative, live-estimated, and cumulative task fuses.

## Parallelism and integration

ACP v1 projects using decomposition v2 default to four workers. Admitted workers
run in detached Git worktrees from an immutable base and have task-private
temporary/build directories. The one logical manager may activate multiple
dependency-ready DAG roots when the compiled semantic conflict graph proves
their mutation regions independent, including disjoint regions of the same
file.

Workers never advance the canonical repository. A completed worker candidate
is submitted to the Source Code Transaction Manager as a standard Git patch
with its base commit, exact changed paths, and ACP write capability. SCTM is a
single FIFO canonical writer. Under an exclusive repository lock it attempts a
three-way apply against the current HEAD, mechanically enforces the capability,
runs focused validation in a staging worktree, and commits atomically. A clean
same-file application is accepted; a genuine region collision returns a
bounded conflict delta for deterministic replan. Original worker identities,
immutable requests, validation logs, results, conflict evidence, and integrated
HEADs remain durable. See `sctm-v1.md`.

`HARNESS_WORKER_PARALLELISM=0` selects online machine capacity capped by
`HARNESS_WORKER_PARALLELISM_HARD_MAX` (four by default); it never means
unbounded launch. Legacy/non-ACP projects remain serial unless explicitly
configured with the isolated provider.

## Token-mining telemetry

`metrics.env` and `transactions.tsv` report broker hit rate, initial and added
context bytes, context amplification, structural and authority decisions,
suspension/resumption, capability deferrals, integrations, discovered/planned
edge ratio, and an explicitly labelled byte-based proxy for model discovery
tokens displaced by deterministic broker answers. Local broker work always
records zero model tokens. Project efficiency reporting remains authoritative
for actual model tokens per verified semantic facet.
