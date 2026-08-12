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

Accepted decisions, gate results, task impact manifests, and debt state are
then maintained through controlled harness commands under `control/architecture`.
