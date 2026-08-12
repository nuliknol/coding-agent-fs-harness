# Architecture guard registry template

Copy this directory, replace the illustrative widget rows with project-specific
records, and keep every header byte-for-byte. Values are tab-separated; use `-`
for an intentionally empty identifier list.

`SPECIFIED` invariants cite governing specification text. `DERIVED` invariants
must be necessary consequences of specified behavior. `PROPOSED` invariants are
advisory and cannot appear in a node binding until the governing requirement is
approved. Every plan node needs one binding. Every API, representation,
ownership, serialization, concurrency, or error-model dependency needs an edge
contract. A consumer directly depends on its edge producer.

Every enforceable invariant's `affected_nodes` list may contain only nodes whose
bindings include that invariant. Do not classify a contract-decision node as
runtime-affected when enforcement belongs to implementation descendants.
Invariant commands, edge compatibility checks, and lane/component health gates
use focused selectors. A broad aggregate may be collected as baseline evidence
only when its nonzero status is explicitly tolerated and an owned result is
asserted separately. Set `HARNESS_BROAD_GATE_REQUIRED=1` in a validation command
only when the human-owned specification explicitly makes whole-project
aggregate success part of acceptance.

At least one enforceable invariant and one `CRITICAL` cumulative health gate are
required. The gate should trigger after the coherent component group it checks;
its `depends_on` field names prerequisite DAG nodes. Validation values are shell
commands executed from the project repository. Use `REVIEW` only for an
invariant or edge that cannot be mechanized; health gates always use commands.

Initialize the immutable registry before registering the DAG:

```text
manager-init-architecture ENV_FILE ARCHITECTURE_SOURCE_DIR
manager-init-project-plan ENV_FILE DAG_FILE
```

If an installed registry itself is defective, stop the project and use the
operator-controlled revision transaction. It validates the complete candidate
against the durable DAG, preserves all decision/health/debt ledgers, and saves
the previous registry under `control/architecture/revisions/`:

```text
harness-revise-architecture ENV_FILE ARCHITECTURE_SOURCE_DIR REVISION_NOTE_FILE
```

Exception: an exact one-node, dependency-free, `LOW`/`LUNA`
`TEST_IMPLEMENTATION` DAG does not need hand-authored sidecars. Registering that
DAG automatically generates the minimal profile: one specified test obligation,
no decisions or edges, one binding, one critical focused-validation health gate,
and no debt. Any production-code, contract, multi-node, dependent, broad-scope,
or Terra task still requires the explicit architecture registry above.

Accepted decisions, gate results, task impact manifests, and debt state are
then maintained through controlled harness commands under `control/architecture`.
