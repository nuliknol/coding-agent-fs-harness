# Operator architecture reassessment resolution

Resolution-Action: REARM_AFTER_HARNESS_BUG
Harness-Fix-Commit: 2fe2a08

The immutable plan node is a zero-write verification leaf whose validation is
the review-attested descriptor `FOCUSED: IT-A19-SOURCE-001 source-only
requirement audit.` Recovery revisions 12 through 16 replaced that oracle with
the invented executable `source-audit-evidence-check` and exhausted the root
replan budget proving that the nonexistent program could not be resolved.

Harness 5.18.36 restores the immutable review descriptor on read-only recovery
assignments before execution. Preserve all raw counters, rejected results, and
source-audit ordering evidence. Open one fresh bounded liveness epoch so the
worker records a concrete source-only observation under the named oracle and
the manager independently reviews that evidence; do not authorize repository
mutation or a binary command before the audit passes.
