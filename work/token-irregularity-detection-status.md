# Convergence Irregularity Detection Status

Updated: 2026-08-17

## Progress

- [x] Audited token accounting, complexity observations, criterion ledgers,
  patch diagnostics, Context Closure admission, focused validation, repository
  indexing, model policy, liveness, and supervisor interlocks.
- [x] Defined three severities and fail-closed ownership boundaries.
- [x] Added configuration defaults/validation and append-only warning, task
  quarantine, and project-integrity records.
- [x] Added relative-token, context-amplification, accounting-integrity, no-gain,
  non-shrinking decomposition, patch-churn, state-oscillation, closure-bypass,
  model-policy, and index-overuse detectors.
- [x] Added per-root and project total tokens-per-verified-facet reporting,
  since-boundary no-gain windows, and append-only verified-facet interval costs.
- [x] Added explicit integrity resolution plus status/watch integration.
- [x] Completed focused detector tests and the full Python suite; completed the
  full harness, Codex JSONL, decomposition-v2, Luna-only, root-liveness,
  Context Closure, startup transaction, leaf-goal, repository index,
  specification review, supervisor barrier, SCIP importer, architecture,
  dependency, active-revision, and manager-context regression suites.
- [ ] Push development, pull production, and verify live adoption.

## Current implementation notes

- `EFFICIENCY_WARNING` is evidence-only on its first occurrence.
- A repeated relative/context episode quarantines only its exact immutable task
  revision; a smaller successor remains launchable.
- Missing/decreasing/extremely inconsistent accounting, closure bypass,
  Luna-only model bypass, patch-only tool use, and duplicate completed index
  digests stop all agent launches until an explicit resolution is archived.
- Existing roots acquire convergence baselines lazily. Newly initialized roots
  establish the baseline before their first worker episode.
- No new agent retry or stronger-model fallback was introduced.

## Safety constraints

- The three 500,000-token investigation fuses are unchanged.
- Detection cannot automatically resolve an anomaly or reset monotonic
  liveness/token history.
- No detector authorizes Sol/Terra fallback or repository exploration.
