# Persistent goal remediation

Resume the same persistent project goal. The Terra manager rejected completion
and produced the attached completion addendum.

The persistent goal is a plain-language instruction only. Do not invoke
`create_goal`, `get_goal`, `update_goal`, or any other goal-management tool.
Never mark an internal goal blocked or wait in the goal subsystem. If a genuine
external dependency remains after all useful repository-local corrections are
complete, preserve fail-closed behavior, report exact evidence, and end the
turn normally so Terra can judge it. If runtime policy rejects a command,
adapt it to a non-destructive equivalent or a fresh unique temporary path
instead of retrying the rejected form or stopping progress.

Treat every `ADD-NNN` finding as required work, but keep the immutable original
specification authoritative. Inspect the evidence yourself, then implement all
valid corrections in one coherent pass. Refactor architectural or design
problems when the addendum shows they prevent correct specification behavior.
Do not patch only the visible symptom if the underlying design would leave the
feature incomplete.

The repository owner gives you full authority to make any repository-local
source, build, test, documentation, refactoring, replacement, or deletion
change needed to complete the specification and addendum. No additional
authorization is required. Scope labels, ownership labels, baseline wording,
and the breadth of a necessary change are not blockers.

Use only the harness-provided canonical repository baseline to identify
worker-authored changes. Commit hashes mentioned in specification metadata are
historical provenance, not cleanup targets. If an addendum treats content
already present in the canonical baseline as your out-of-scope change, that
evidence is invalid: preserve the baseline content and report the conflict.
Do not run destructive Git or filesystem cleanup merely to shrink a diff.
A tracked file may be deleted or replaced when that is genuinely necessary to
implement an exact governing specification requirement.

After resolving the entire addendum, re-read the complete specification and
look for connected omissions that the manager did not explicitly list. Build,
run the allowed smoke test, and add at most one focused regression test for a
bug you fixed. Continue autonomously until maximum honest completion is reached.

Do not stop after describing a plan or fixing only the first finding. Do not
modify harness state, immutable inputs, the configured source specification,
or review/addendum files. Follow the prototype/feature-first development
policy; do not expand the task into production hardening or a large testing
project.
