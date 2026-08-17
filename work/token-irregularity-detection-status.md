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
- [x] Pushed commit `8f9c1e7`, fast-forwarded production, stopped old-code
  supervisors, and restarted the runnable projects on the deployed code.

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

## Production adoption

- `compmod-wc-2` and `compmod-wc-3` restarted with new manager/worker
  supervisors and are performing fresh Luna-only replans.
- The installed HIGH/TERRA documentation assignment in `compmod-wc-3` was
  retired before worker launch and queued for LOW/LUNA re-decomposition.
- Live enforcement then caught a second HIGH/TERRA recovery draft before its
  worker launched. The final publisher boundary now rejects every non-LOW/LUNA
  executable draft in `luna_only` mode, allowing the same bounded planning turn
  to correct it instead of installing another policy-violating task.
- `compmod-wc-4`, `dplm-final-v2`, and `dpvis-w2-a2` remain stopped at their
  durable `ARCHITECTURE_REASSESSMENT_REQUIRED` boundaries; their evidence and
  counters were not reset.
- Live status exposes convergence efficiency and all three irregularity counts.

## Safety constraints

- The three 500,000-token investigation fuses are unchanged.
- Detection cannot automatically resolve an anomaly or reset monotonic
  liveness/token history.
- No detector authorizes Sol/Terra fallback or repository exploration.
