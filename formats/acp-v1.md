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
Request-Type: CONTEXT|SCOPE|PREREQUISITE|SPLIT
Request-Kind: <typed classification>
Identifier: <one exact symbol, path, criterion, or boundary>
Reason: <one bounded sentence>
Workspace-Fingerprint: sha256:<digest>
Request-Fingerprint: sha256:<digest>
Evidence-Artifact: -|<content-addressed path>
Assignment: <immutable assignment path>
Requested-At: <UTC timestamp>
```

`CONTEXT` kinds are:

```text
TYPE_DEFINITION
SYMBOL_DEFINITION
CALLER_CONTRACT
CALLEE_CONTRACT
FAILING_ASSERTION
TEST_OWNER
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

## Parallelism

ACP negotiation is independent of scheduling. The deployed safe default is one
worker. The current deployment rejects a configuration above one (and also
requires worktree mode as a prerequisite) until capability-lease and
deterministic integration providers are available. Zero is never unbounded; it
resolves to the scheduler's safe bounded capacity, currently one.
