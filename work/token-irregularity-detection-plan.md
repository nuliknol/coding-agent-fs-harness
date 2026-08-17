# Convergence Irregularity Detection

Status: implementation plan

Created: 2026-08-17

## Objective

Detect inefficient or integrity-breaking execution before repeated Luna,
planning, validation, indexing, or recovery turns can consume project-scale
tokens without closing specification obligations. The existing 500,000-token
authoritative invocation, live-estimate invocation, and cumulative worker-task
fuses remain unchanged and independent.

## Severity and enforcement

| Severity | Meaning | Enforcement |
| --- | --- | --- |
| `EFFICIENCY_WARNING` | One unusual but potentially legitimate episode | Record durable evidence; do not interrupt accepted progress |
| `TASK_RESOURCE_ANOMALY` | A repeated or deterministic leaf-local inefficiency | Quarantine that immutable task/revision and return its root to decomposition |
| `PROJECT_INTEGRITY_ANOMALY` | Accounting, closure, model-policy, or state-authority failure | Suppress every later agent launch pending an explicit corrective resolution |

Warnings and anomalies use append-only TSV ledgers plus human-readable control
records. Anomaly identity is the category, task/root, and normalized evidence
fingerprint. Raw source, command output, and prompts are not copied into the
ledger.

## Detectors

1. **Relative token regression** — compare an episode with its declared p95
   and, after enough samples, the median for the same model and leaf type. The
   first outlier warns; a repeated outlier quarantines the immutable leaf.
2. **Tokens without verified gain** — account worker, planning, replan, review,
   and remediation deltas from the last verified criterion/facet boundary. A
   multi-episode token window without a new facet stops the root for
   architecture/decomposition investigation.
3. **Non-shrinking decomposition** — reject a child whose obligation count,
   complexity, path breadth, and predicted token cost do not shrink relative
   to its declared parent.
4. **Repeated diagnostics and patch churn** — retain semantic diagnostic and
   patch digests. Repeated diagnostics stop immediately; multiple unsuccessful
   distinct patches produce a task anomaly instead of another unchanged leaf.
5. **Validation inflation** — reject unfiltered/global validation from focused
   leaves and record the rejected contract as an efficiency irregularity.
6. **Context amplification** — record repeated predecessor evidence reads;
   repeated amplification quarantines the leaf. Existing command-level output
   and repeat fuses remain authoritative.
7. **Index/tool overuse** — SCIP and Joern remain serialized, resource-bounded,
   and digest-cached. A requested second expensive build for an already
   completed digest is an integrity anomaly instead of another JVM/index run.
8. **Accounting inconsistency** — missing successful-turn usage, decreasing
   cumulative thread usage, ledger/invocation delta disagreement, or an extreme
   authoritative/live-estimate mismatch pauses the project.
9. **State oscillation** — repeated publication of the same first-unmet
   criterion without new verified evidence stops the root for reassessment.
10. **Closure bypass** — a Luna invocation reaching execution without a READY,
    nonempty compiled Context Closure in an enforcing mode pauses the project.
11. **Model-policy violation** — a Luna-only project attempting a non-Luna
    model or Terra execution role pauses the project before provider launch.

## Primary metric

For each root and project, publish:

```text
tokens_per_verified_facet =
    worker + planning + replan + review + remediation processed-token deltas
    / newly verified criterion facets
```

The metric also records tokens and paid episodes since the last verified facet.
It is diagnostic when no facet exists and becomes the input to the no-gain
circuit breaker once a baseline has been established.

## Compatibility and rollout

- Existing projects establish a no-gain baseline from current durable state;
  historical tokens do not retroactively create a new anomaly.
- Absolute 500,000-token fuses and all existing liveness/resource guards are
  unchanged.
- Existing deterministic guards gain anomaly events; they do not receive extra
  model retries.
- New project-integrity records require an explicit resolution note. Task
  anomaly records are immutable-revision quarantine evidence and do not block a
  correctly decomposed successor revision.
