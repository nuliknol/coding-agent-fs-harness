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

# Harness context

Project: `benchmark-light-pbnfc-html8-light-20260728a`

Repository: `/var/home/mf/coding-agent-fs-harness/benchmark/light/runs/pbnfc-html8-light-20260728a/repository`

Immutable specification: `/var/home/mf/coding-agent-fs-harness/benchmark/light/runs/pbnfc-html8-light-20260728a/state/projects/benchmark-light-pbnfc-html8-light-20260728a/inputs/specification.txt`

Development policy: `/var/home/mf/coding-agent-fs-harness/benchmark/light/runs/pbnfc-html8-light-20260728a/state/projects/benchmark-light-pbnfc-html8-light-20260728a/inputs/development-policy.txt`


# Manager-authored goal

# Persistent Worker Goal

Own and complete the entire `pbnfc` project specification in this repository—not a single subtask. First inspect `AGENTS.md`, `SPECIFICATION.md`, the current repository, and the immutable development policy; plan the required work internally, then immediately implement the complete working feature. Preserve correct existing work, and repair incomplete or architecturally unsound work where necessary.

Build a self-contained ISO C11/POSIX-pthreads command-line program at `bin/pbnfc`, built by `make clean all` with `-std=c11 -Wall -Wextra -Werror -pedantic -pthread`, supporting exactly:

```text
bin/pbnfc --grammar PATH --input PATH [--start NAME] [--stats]
```

Implement the complete BNF grammar compiler: whitespace/comments, required first `%start NAME`, optional `%token IDENT|STRING|TEXT`, productions with `::=`, `|`, `;`, epsilon alternatives, quoted exact terminals with `\'` and `\\`, `$IDENT`/`$STRING`/`$TEXT`, symbol resolution, duplicate-rule and undefined-reference errors, start override, and direct/indirect left-recursion detection. Do not hard-code the supplied HTML grammar or tag hierarchy.

Implement the markup lexer for compact HTML-like input: literal `<`, `>`, `/`, `=` inside tags; identifiers matching `[A-Za-z_:][A-Za-z0-9_.:-]*`; single/double quoted strings with quote/backslash escapes; maximal non-whitespace `TEXT` outside tags; accurate byte offset, line, and column tracking; and errors for invalid bytes or unterminated tags/strings.

Implement a safe general chart recognizer that accepts only when the complete token stream matches, supports epsilon, right recursion, nested expansion, and ambiguity safely, and uses one persistent pool of exactly eight pthread workers for one document. The coordinator must distribute prediction/completion closure waves and scanning work across all workers; workers must write only thread-local candidates against read-only snapshots; the coordinator must merge, deduplicate, and order results deterministically between waves. Reuse the pool until parsing ends, ensure all eight workers do real chart work on the stress case, track positive per-worker task counts and positive rounds, prevent data races, handle allocation failures, and join workers on every normal or error exit.

Honor all observable output and exit contracts:

- Success: exit 0 and exactly `ACCEPT tokens=N`, with `--stats` appending deterministic `workers=8 active_workers=8 rounds=N tasks=N,N,N,N,N,N,N,N`.
- Valid grammar but nonmatching markup: exit 1 with one `REJECT ` line containing decimal `offset=`, `line=`, `column=`, and nonempty `expected=`.
- CLI, grammar lex/parse, undefined symbol, left-recursion, or markup-lexing failures: exit 2 with one useful `GRAMMAR_ERROR ` line.
- Without `--stats`, never emit timing or scheduling-dependent output.

Keep implementation in understandable `src/` and `include/` modules covering CLI, diagnostics/locations, grammar lexer/parser and AST validation, markup lexer, chart representation/recognition, and worker pool. Avoid global mutable parser state and free allocations on normal exits. Update `README.md` with grammar syntax, markup tokenization, parallel merge invariants, limitations, examples, outputs, and exit statuses. Provide `make test`, but follow the prototype/feature-first policy exactly: keep changes small and direct; use only build checking, one happy-path smoke test, and a regression test only when fixing a bug—no broad test suites, mocks, generic frameworks, production infrastructure, unrelated refactors, or broad abstractions.

Internally retain the specification’s ten independently verifiable implementation areas: strict build/CLI/diagnostics; BNF lexing; AST and validation; markup lexing; sequential chart semantics; persistent pool; parallel closure; parallel scanning/stats; hierarchical grammar integration/rejection/stress; and final build/testing/README validation. Do not stop at a plan, analysis, scaffold, placeholder, progress report, or partial implementation while useful repository-local work remains. Continue autonomously through integration, compilation failures, debugging, and the allowed smoke tests. Before declaring readiness, reread the complete specification and verify every required contract, then run:

```text
make clean all
../grader.sh "$PWD"
```

Finish with a concise implementation and verification report stating what changed, how to run and manually verify it, and any genuine limitations.

GOAL_READY