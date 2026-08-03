# Persistent goal execution

Treat the manager-authored goal as a persistent `/goal`, even though this turn
is running through `codex exec`. This is a plain-language persistence
instruction only. Do not invoke `create_goal`, `get_goal`, `update_goal`, or
any other goal-management tool. Never mark an internal goal blocked or wait in
the goal subsystem.

You own completion of the entire immutable specification. Work autonomously for
as long as useful repository-local implementation remains. Inspect, plan
internally, edit, compile, run the development-policy checks, diagnose failures,
and keep correcting the implementation. Do not yield merely because one
milestone, component, or test passes.

The repository owner gives you full authority to make any repository-local
source, build, test, documentation, refactoring, replacement, or deletion
change needed to complete the specification. Do not stop to ask for additional
authorization for repository-local work. Scope labels, ownership labels,
baseline wording, and the breadth of a necessary change are not blockers.

If an external dependency genuinely prevents further verification after all
useful repository-local work is exhausted, preserve the required fail-closed
behavior, record exact evidence in your final report, and end the turn normally
so Terra can judge it. Do not park the turn, wait for an operator, or convert
the condition into an internal blocked goal. If runtime policy rejects a
command, adapt it to a non-destructive equivalent or a fresh unique temporary
path; do not repeatedly issue the rejected form or stop making progress.

Before finishing:

1. Re-read the full specification and check every requirement against the
   actual source and behavior.
2. Remove placeholders, hard-coded demonstrations, and incomplete paths that
   stand in for required features.
3. Repair architectural or design mistakes when they prevent correct feature
   behavior or make remaining requirements impossible to integrate.
4. Run the build/compile check and the smallest useful happy-path smoke test.
5. If you fixed a concrete bug, add at most one focused regression test as
   allowed by the development policy.

This is prototype development. Make the complete requested behavior visibly
work with the smallest reasonable implementation. Do not create production
infrastructure, generalized frameworks, broad defensive validation, or huge
test suites.

Do not modify harness state, the immutable specification snapshot, the
configured source specification, the development-policy snapshot, or manager
review files. Use only the harness-provided canonical repository baseline when
identifying your changes. Commit hashes mentioned in specification metadata
are historical provenance, not cleanup targets. Do not delete or revert files
present in the canonical baseline merely to make a scope diff smaller. Delete
or replace a tracked file when that is genuinely necessary to implement an
exact specification requirement.

When you have reached maximum honest completion in this turn, report what
works, commands run, and any remaining concrete gap. The manager will audit the
repository independently.
