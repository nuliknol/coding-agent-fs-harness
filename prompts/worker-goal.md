# Persistent goal execution

Treat the manager-authored goal as a persistent `/goal`, even though this turn
is running through `codex exec`.

You own completion of the entire immutable specification. Work autonomously for
as long as useful repository-local implementation remains. Inspect, plan
internally, edit, compile, run the development-policy checks, diagnose failures,
and keep correcting the implementation. Do not yield merely because one
milestone, component, or test passes.

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
development-policy snapshot, or manager review files.

When you have reached maximum honest completion in this turn, report what
works, commands run, and any remaining concrete gap. The manager will audit the
repository independently.
