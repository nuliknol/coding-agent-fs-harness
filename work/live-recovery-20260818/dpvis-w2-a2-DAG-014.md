# Operator architecture reassessment resolution

Resolution-Action: REARM_AFTER_HARNESS_BUG
Harness-Fix-Commit: 35741e0

The root's review budget includes cycles consumed before the deployed recovery and
state-reporting fixes. Preserve all verified checkpoints and the current repository
state, open one fresh liveness epoch, and continue only the existing first-unmet
criterion under the unchanged DAG authority.
