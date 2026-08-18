# Operator architecture reassessment resolution

Resolution-Action: REARM_AFTER_HARNESS_BUG
Harness-Fix-Commit: 0843c48

The first post-5.18.33 continuation compiled a valid Context Closure graph cut,
then immediately reached the inherited lifetime replan epoch. Harness 5.18.34
fixes the deterministic continuation compiler so it emits exactly one canonical
Task-ID, Task-Root, and Target-Criterion for assignments that do not contain a
legacy Root-Criterion field. Preserve all raw counters, checkpoints, and the
pending `CONTEXT_CLOSURE_REPAIR / GRAFT_GRAPH_CUTS` transaction; open one
bounded epoch to publish that already compiled cut without manager inference.
