# Harness Throughput Improvement Plan

Status: COMPLETE — IMPLEMENTED, DEPLOYED, AND LIVE-RECOVERED
Started: 2026-08-18
Completed: 2026-08-18

## Objective

Reduce control-plane amplification so dependency-ready workers normally reach a
useful checkpoint or acceptance in one bounded episode, while preserving strict
mutation authority, deterministic evidence, append-only ACP history, isolated
worktrees, and one logical manager. Four-worker capacity must be fed by genuinely
independent work rather than parallelizing rejection loops.

## Baseline

The live six-project sample recorded 2,096 agent invocations, 657 automatic
replans, 321 rejected reviews, 173 denied context expansions, and 206 fresh CMake
configurations for 22 completed plan nodes. All projects had capacity four but no
safe dependency-ready node at the sample boundary. One terminal story result was
silently suppressed after an uncommitted manager review.

## Phase 1 — Terminal control-plane liveness

- [x] Give an unchanged uncommitted manager review a bounded fresh-context retry.
- [x] Persist retry identity/count by immutable result fingerprint.
- [x] After exhaustion, create an explicit paused review state; never leave a
      terminal result dormant while status says running.
- [x] Make status/watch distinguish active inference, scheduled retry, and paused
      manager review.
- [x] Add regression coverage for retry success, retry exhaustion, restart, and
      unchanged-fingerprint suppression.

## Phase 2 — Context Broker fast path

- [x] Keep mutation scope unchanged while admitting bounded read-only evidence for
      exact symbols inside declared context/mutation paths.
- [x] Admit proven one-hop type, caller, callee, producer, consumer, mutation,
      owner, test, validation, and build-target neighbors.
- [x] Add a bounded exact `SOURCE_WINDOW` request for declared or proven-neighbor
      indexed paths.
- [x] Preserve the existing four-region, byte, request, duplicate, index-currency,
      and workspace-fingerprint fuses.
- [x] Resume the same worker thread after a grant and add negative tests proving
      unrelated lexical matches remain denied.

## Phase 3 — Deterministic recovery fast paths

- [x] Republish an exact context-only continuation without manager inference when
      the broker or compiled closure proves the addition and mutation authority is
      unchanged.
- [x] Execute compiled Context Closure graph-cut children without asking a manager
      to rediscover their paths, symbols, order, or acceptance boundary.
- [x] Route exact normalized build/test-owner evidence through the deterministic
      broker before creating `NEEDS_DECOMPOSITION`.
- [x] Retain manager inference for mutation-scope changes, architecture choices,
      competing prerequisite strategies, specification ambiguity, and human
      authority.
- [x] Preserve raw counters, task identity, ACP transactions, and restart recovery.

## Phase 4 — Incremental validation and build evidence

- [x] Replace unconditional CMake `--fresh` rewriting with cache-identity checks.
- [x] Reconfigure freshly only for a missing/mismatched source, generator,
      toolchain, or CMake-graph fingerprint; otherwise configure incrementally.
- [x] Enable a configured compiler cache when available without changing commands'
      observable validation semantics.
- [x] Emit validation receipts bound to HEAD, command, source/build identity,
      toolchain, and result.
- [x] Reuse an integration receipt only when every identity field matches exactly.

## Phase 5 — Throughput and parallelism metrics

- [x] Add implementation yield, control amplification, negotiation-to-
      implementation ratio, ready width, safe-ready width, critical-path length,
      maximum DAG width, and worker-slot utilization.
- [x] Record scheduler occupancy transitions durably enough to survive restart.
- [x] Expose the metrics through `harness-decomposition-metrics`, statistics,
      status, and architecture scorecards.
- [x] Add a pre-execution decomposition diagnostic when configured capacity cannot
      be exposed, while permitting a documented genuinely serial plan.

## Phase 6 — Precise capabilities and conflict graph

- [x] Require exact files for source-changing Luna nodes when required symbols can
      be resolved; reject unnecessarily broad directory mutation authority.
- [x] Compile optional symbol/region mutation capabilities from a current index.
- [x] Verify every patch hunk is contained by its assigned path and, when declared,
      symbol/region authority.
- [x] Compile a conflict graph from overlapping paths/regions/symbols plus public
      representation, architecture, ownership, serialization, and concurrency
      authorities.
- [x] Select up to configured capacity from dependency-ready nodes with a greedy
      conflict-free scheduler; retain isolated worktrees and serialized integration.
- [x] Treat unresolved textual integration conflicts as explicit integration events,
      never as permission to weaken semantic conflicts.

## Phase 7 — Critical-path-aware decomposition

- [x] Compute node count, critical path, maximum width, average ready width, and
      conflict-reduced width before plan installation.
- [x] Ask decomposition repair to shorten avoidable critical paths and split shared
      contract producers from independent adopters.
- [x] Never invent concurrency across true representation, ownership, ordering, or
      producer/consumer dependencies.
- [x] Retain a machine-readable rationale when safe maximum width is below worker
      capacity.

## Phase 8 — Manager event batching

- [x] Add an append-only manager inbox for independent completed results and semantic
      ACP requests.
- [x] Compile bounded review packets per event and allow one manager inference to
      emit multiple independently validated decisions.
- [x] Commit each decision independently under existing project/task locks with
      per-event idempotency and partial-failure isolation.
- [x] Keep one logical manager and preserve every per-task ACP/review transaction.

## Phase 9 — Build and validation brokers

- [x] Add deterministic source-to-target, configure-required, minimal-target,
      executable, selector, and dependency-artifact queries.
- [x] Normalize the first causal validation error and make it available to Context
      Broker resolution without an exploratory model turn.
- [x] Key persistent/private build state by repository identity, base HEAD,
      worktree/source identity, configure arguments, generator, and toolchain.
- [x] Never share mutable build directories across simultaneous worker worktrees.

## Verification and rollout

- [x] Add focused unit/integration tests for every phase and preserve existing ACP,
      Context Closure, decomposition, supervisor barrier, repository-index,
      architecture, liveness, and full harness suites.
- [x] Run syntax, formatting, module-boundary, and complete regression checks.
- [x] Record before/after throughput metrics on retained fixtures.
- [x] Deploy development commits to production only after tests pass and tree
      identity is verified.
- [x] Inventory paused production roots after deployment, resolve only incidents
      covered by installed fixes, restart those harnesses, and confirm live progress.

Production version: 5.18.36

Live recovery evidence:

- `compmod-wc-3` published deterministic closure revision 80 and launched its
  Luna worker after the closure-cut fingerprint fix.
- `dplm-final-v2` published deterministic closure revision 163 and launched its
  Luna worker after the same fix.
- `dpvis-w2-a2` resumed a preserved revision after deterministic build-broker
  evidence removed the repeated target-discovery loop.
- `compmod-wc-4` resumed its normalized zero-write continuation without a false
  mutation-scope expansion.
- `mf-story-a19-r2` was rearmed after the read-only validation-oracle fix;
  revision 17 retained the original `FOCUSED:` oracle and launched a Luna
  worker instead of testing the invented `source-audit-evidence-check` program.
- The post-recovery fleet snapshot contained no paused project.

## Completion criteria

- No terminal result can remain silently dormant.
- Direct, proven read-context requests normally grant and resume without manager
  inference.
- Deterministic repairs do not consume semantic manager turns.
- CMake configuration is fresh only when cache identity requires it.
- Decomposition reports theoretical and observed parallelism.
- Independent symbol/region work can use isolated worker capacity safely.
- Batched manager and build/validation broker paths preserve per-task authority and
  audit history.
- Production is deployed, paused affected roots are explicitly recovered, and the
  live fleet shows forward progress.
