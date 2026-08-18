# ACP implementation plan

## Objective

Generalize the harness's existing typed Context Closure expansion and dependency-wait mechanisms into a durable Agent Control Protocol (ACP) that improves verified work per token without weakening specification authority, Context Closure admission, or resource-investigation fuses.

## Non-negotiable invariants

- Initial Context Closure remains required for Luna execution. ACP repairs decisive omissions; it does not excuse weak capsules.
- The specification and accepted architecture remain authoritative. Workers submit observations and requests; they never grant themselves scope, capabilities, prerequisites, or DAG mutations.
- Deterministic repository questions go to the Context Broker before any model.
- Every inference process is ephemeral. Filesystem state, supervisors, leases, indexes, and durable provider thread IDs own waiting and resumption.
- The 500,000 authoritative, live-estimated, and cumulative worker-task token fuses remain unchanged.
- Duplicate requests, context/scope amplification, no-progress negotiation, stale authority, and conflicting capability leases are hard protocol anomalies.
- ACP messages reference bounded data-plane artifacts by digest/path; they do not carry repository dumps.
- Discovered DAG history is append-only and distinguishable from planned nodes and edges.
- Parallel execution is opt-in and isolated. The safe default remains one worker until a repository supplies disjoint workspaces, capability leases, and deterministic integration.

## Delivery phases

1. Add a versioned ACP message envelope, append-only event ledger, request state, schema validation, idempotency, stale-workspace rejection, and operational status/metrics.
2. Promote the existing typed context resolver into the mandatory deterministic Context Broker for symbol, type, caller/callee, producer/consumer, test, owner, build-target, and failing-assertion requests in every required-closure Luna mode.
3. Add worker suspension and same-thread resumption for context, scope, prerequisite, and split requests. Deterministic grants bypass manager inference; authority-changing requests are queued for one logical manager.
4. Add manager adjudication with exact grant/deny/prerequisite/split decisions and append-only discovered DAG node/edge records.
5. Add protocol cost, broker-hit, manager-avoidance, context/scope amplification, drift, discovered-graph, and tokens-per-verified-facet telemetry.
6. Add bounded isolated worker cohorts, capability conflict admission, token-aware scheduling, and deterministic integration barriers. Enable only when configured; never treat zero as infinite uncontrolled launch.
7. Run focused and full regression suites, deploy through the dev-push/production-pull workflow, and verify live harness compatibility.

## Success gates

- Existing Context Closure, worker, recovery, token anomaly, and model-policy tests remain green.
- A typed deterministic request resolves without a manager model invocation and resumes the same worker thread.
- A scope/prerequisite/split request releases the inference process and cannot mutate authority until adjudicated.
- Repeated or amplified requests stop locally with durable evidence while all existing token fuses remain active.
- Planned and discovered DAG history is auditable and current dependency readiness reflects accepted discovered prerequisites.
- Metrics report broker hit rate, manager invocations avoided, ACP tokens/events per verified facet, added context/scope ratios, and discovered/planned graph ratios.
- Parallel cohorts cannot acquire overlapping write capabilities and remain disabled by default.
