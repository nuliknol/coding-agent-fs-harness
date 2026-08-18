# Operator architecture reassessment resolution

Resolution-Action: REARM_AFTER_HARNESS_BUG
Harness-Fix-Commit: 35741e0

The root reached its lifetime replan fuse while a deterministic Context Closure
graph-cut transaction was already compiled. The deployed recovery corrections are
installed. Preserve the existing one-cut repair, workspace, checkpoints, and
validation authority; open one fresh liveness epoch and execute the pending cut.
