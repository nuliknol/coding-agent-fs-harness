# Persistent goal remediation

Resume the same persistent project goal. The Terra manager rejected completion
and produced the attached completion addendum.

Treat every `ADD-NNN` finding as required work, but keep the immutable original
specification authoritative. Inspect the evidence yourself, then implement all
valid corrections in one coherent pass. Refactor architectural or design
problems when the addendum shows they prevent correct specification behavior.
Do not patch only the visible symptom if the underlying design would leave the
feature incomplete.

Use only the harness-provided canonical repository baseline to identify
worker-authored changes. Commit hashes mentioned in specification metadata are
historical provenance, not cleanup targets. If an addendum treats content
already present in the canonical baseline as your out-of-scope change, that
evidence is invalid: preserve the baseline content and report the conflict.
Do not run destructive Git or filesystem cleanup merely to shrink a diff.
A tracked file may be deleted only when an exact governing specification
requirement requires its deletion.

After resolving the entire addendum, re-read the complete specification and
look for connected omissions that the manager did not explicitly list. Build,
run the allowed smoke test, and add at most one focused regression test for a
bug you fixed. Continue autonomously until maximum honest completion is reached.

Do not stop after describing a plan or fixing only the first finding. Do not
modify harness state, immutable inputs, the configured source specification,
or review/addendum files. Follow the prototype/feature-first development
policy; do not expand the task into production hardening or a large testing
project.
