# ACP implementation status

Updated: 2026-08-17

Overall: IN PROGRESS

## Completed

- Reviewed `work/acp-proposal.md` against the deployed Context Closure, worker continuation, dependency wait, recovery, token accounting, and serialized DAG scheduler.
- Confirmed the existing typed context-request resolver, same-thread continuation, token-free dependency waiting, append-only criterion refinement, and convergence metrics are reusable ACP foundations.
- Recorded the implementation phases, safety invariants, parallelism constraints, and success gates in `work/acp-implementation-plan.md`.
- Added ACP v1 durable control state: validated typed envelopes, stable request/workspace fingerprints, append-only events, content-addressed evidence artifacts, pending/archive state, discovered-graph claims, and operational metrics.
- Added duplicate-request, stale-authority, request-count, added-context, and negotiation-without-progress investigation fuses without changing any existing 500,000-token fuse.
- Generalized the deterministic Context Broker to cover exact symbol/type definitions, callers, callees, failing assertions, indexed tests, build/concept ownership, producers, consumers, and representation writers using indexed SCIP/Joern/build evidence.
- Integrated broker requests into patch-only Context Closure: accepted facts are bounded, provenance-bearing, recorded in ACP, and resume the same durable Luna thread; rejected or amplified requests stop locally.
- Added typed `SCOPE`, `PREREQUISITE`, and `SPLIT` handoffs. They preserve the worker thread, terminate the ephemeral Luna process, record append-only discovery history, and enter existing manager decomposition without granting worker authority.
- Added manager instructions that require independent substantiation and prohibit ACP-driven Terra/Sol implementation or repository-wide Luna exploration.
- Added `harness-acp-status`, focused ACP tests, and expanded deterministic resolver tests. Initial syntax and focused tests pass.
- Added manager disposition linkage (`MANAGER_ACCEPT`, `MANAGER_CHECKPOINT`, and `MANAGER_REPLAN`) so each negotiated boundary remains auditable through review rather than ending at the worker request.
- Extended ACP deterministic fact negotiation to both `required` and `patch_only` Context Closure modes. A denied required-mode fact now returns a bounded `CONTEXT_INCOMPLETE` handoff rather than repository exploration.
- Added ACP convergence telemetry to `harness-decomposition-metrics`: broker hit rate, avoided manager invocations, added context bytes, requests per verified item, discovered/planned graph ratio, and existing tokens per verified facet.
- Added initial-context versus broker-extension amplification telemetry and manager-disposition counts; normal required-closure Luna prompts now expose the same typed structural negotiation as patch-only Luna.
- Added the normative protocol description in `formats/acp-v1.md` and operator documentation in `README.md`.
- Enforced serial fail-closed scheduling: zero resolves to safe bounded capacity and values above one are rejected until isolated capability leases and deterministic integration are actually available.
- Live restart exposed and fixed a pre-existing patch-only empty-commit orphan: an identical remove/add proposal with passing trusted validation now becomes `PATCH_ONLY_ALREADY_SATISFIED`, and exact machine metadata strips Markdown trailing-space line breaks before result publication.
- Passed ACP, irregularity, Context Closure (76 focused Python cases across resolver/compiler helpers), repository-index, Luna-only convergence, leaf-goal, decomposition-v2, supervisor barrier, Git dependency, active plan revision, core harness, architecture redesign, autostart, decomposition startup, manager rotation, root liveness, specification review/satisfiability, and Codex JSONL/resource-fuse suites.

## In progress

- Final code review, deployment transaction, and live production compatibility verification.

## Pending

- Deploy through dev push / production pull and verify the production command surface and active harness state.

## Test notes

- A detached clean worktree at pre-change commit `008690e` confirms that `tests/test-architecture-guards.sh` already stopped at its missing-consumer-artifact expectation because the publish command succeeds and does not create the expected redirected error file. ACP manager hooks are no-ops for that result because it has no `ACP-Request-ID`.
- The same detached pre-change worktree confirms that `tests/test-scip-importer.sh` already stopped at its context-usage fixture expectation: the generated report records `src/calc.c` as used but not changed. ACP does not alter `harness-context-closure-usage`; all resolver/compiler-specific SCIP and Context Closure tests pass.
