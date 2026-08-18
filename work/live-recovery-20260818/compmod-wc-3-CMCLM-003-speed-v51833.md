# Operator architecture reassessment resolution

Resolution-Action: REARM_AFTER_HARNESS_BUG
Harness-Fix-Commit: 0f87b0a

CMCLM-003 exhausted this liveness epoch after revision 78 requested the exact
`rs_computing_claim_gpu_row` type definition and the old Context Broker denied
it. The type is an indexed direct dependency of the assigned GPU normalization
symbols. Harness 5.18.33 admits exact types and direct semantic neighbors while
leaving mutation authority unchanged. Preserve all raw counters, checkpoints,
source state, and the pending `MANAGER_REMEDIATION_CONTEXT_INCOMPLETE`
transition; open one bounded post-fix epoch.
