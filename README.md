# Coding Agent Filesystem Harness — light mode

This branch implements a deliberately small manager/worker loop for prototype,
feature-first development.

One Terra High turn writes a persistent goal for one Luna High coding thread.
Luna works on the complete specification in a long autonomous `codex exec`
turn. Terra then audits the complete repository. If anything is missing, Terra
publishes one exhaustive completion addendum and the harness resumes the same
Luna thread. Stable finding keys detect repeated, non-converging reviews and
trigger one fresh Terra convergence audit. The loop ends when Terra accepts,
the audit identifies a genuine operator-only blocker, or the emergency review
cap is reached.

## Process

```text
immutable specification + prototype development policy
                         |
                         v
              Terra High goal author
                         |
                         v
        one persistent Luna High coding thread
                         |
                         v
         Terra High full-spec repository audit
                    /             \
               ACCEPT             REVISE
                  |                  |
                  v                  v
              complete      exhaustive addendum
                                      |
                                      v
                         resume the same Luna thread
```

The interactive `/goal` command is not used. Terra writes a plain-language goal
that tells Luna to behave as a persistent goal owner: inspect, implement,
compile, debug, smoke-test, re-read the complete specification, and continue
until no useful in-scope work remains. Every correction turn uses
`codex exec resume` with the original Luna thread ID.

Terra review turns are fresh and sparse. They do not inherit a growing manager
conversation. Each review reads the immutable specification, development
policy, repository, worker report, and prior addenda.

## Why use it?

Long autonomous coding runs are efficient, but a model's completion claim is
not an independent acceptance decision. An implementation can pass its visible
tests while still missing edge cases, architectural requirements, or parts of
the governing specification. A separate repository audit improves confidence,
but manually running that audit and relaying every correction adds operator
time, context switching, and repeated setup cost.

The light harness automates that acceptance loop:

- **Luna owns implementation.** A lower-cost model keeps one persistent thread
  for the complete specification, preserving design context across corrections.
- **Terra owns acceptance.** A stronger model performs sparse, fresh
  full-repository reviews and converts concrete gaps into exhaustive addenda.
- **The supervisor owns coordination.** It records every goal, review,
  correction, model trace, and token total, then resumes the worker without
  requiring manual copy-and-paste handoffs.
- **The specification remains authoritative.** The loop ends only when Terra
  accepts the repository or an explicit operator limit pauses it.

This design concentrates the more expensive model on high-leverage review work
while assigning most implementation work to the less expensive model. Reusing
the Luna thread also avoids repeatedly rebuilding the worker's complete project
context. It is intended for unattended, prototype-oriented development where
specification coverage matters more than obtaining the cheapest possible first
pass.

### Benchmark evidence

The reference benchmark used a nontrivial ISO C11 project: a BNF compiler and
HTML-like recognizer with a persistent eight-thread POSIX worker pool,
parallel chart parsing, deterministic merging, diagnostics, and stress tests.
It compared one standalone Terra High run with the light Terra High
manager/Luna High worker arrangement.

| Measure | Single Terra High | Light harness |
|---|---:|---:|
| Public grader | 12/12 | 12/12 |
| Observed completeness | 71.4% | 95.2% |
| API-price-equivalent total cost | $0.8631 | $3.2960 |
| Cost per final C/header line | $0.004543 | $0.001928 |
| Final physical lines per dollar | 220.14 | 518.81 |

The standalone run remained the least expensive way to pass the visible
grader. The light harness cost 3.82 times more in total, but its independent
review loop found and corrected five additional specification failures,
produced a substantially more maintainable implementation, and achieved a
57.57% lower nominal cost per final physical line. Compared with the original
fine-grained full harness, light reduced API-price-equivalent cost by 75.53%.

These figures describe one controlled benchmark, not a universal guarantee.
Model behavior varies by task, and physical lines of code are not a
quality-adjusted unit. The stronger result is the combination of improved
observed completeness, automated acceptance, durable evidence, and lower
orchestration cost than the full harness. See the
[benchmark introduction](benchmarks/README.md) and
[complete comparison report](benchmarks/light-vs-single-terra-high.md) for the
methodology, raw measurements, and limitations.

## Development policy

`DEVELOPMENT_POLICY` is required. At initialization the harness snapshots it
beside the specification. The intended policy is prototype/feature-first:

- implement every specified feature so it visibly works;
- use the smallest reasonable integration;
- require a build/compile check and one happy-path smoke test;
- add one focused regression test only when fixing a concrete bug;
- avoid production infrastructure, broad abstractions, unrelated refactors,
  exhaustive validation, and large test suites.

Terra must reject missing or broken specified behavior, including placeholders
and disconnected implementations. It must not reject merely because the code
lacks production hardening that the specification and policy do not require.

## State model

One supervisor runs the complete sequential loop. Durable phases are:

| Phase | Meaning |
|---|---|
| `GOAL_REQUIRED` | Terra must write the persistent worker goal |
| `WORKER_REQUIRED` | Luna starts or resumes autonomous implementation |
| `REVIEW_REQUIRED` | Terra audits the delivered repository |
| `CONVERGENCE_REQUIRED` | A repeated finding needs one fresh Terra audit |
| `ACCEPTED` | Terra accepted the complete specification |
| `REVIEW_LIMIT_REACHED` | Optional operator limit paused the loop |
| `NEEDS_OPERATOR` | The fresh audit proved an external/specification blocker |
| `TERMINAL_FAILURE` | A non-provider process or protocol error stopped it |

Provider quota and transient failures retry in place. Supervisor restart
preserves the manager goal, Luna thread ID, addenda, review history, token logs,
and repository changes.

The original specification is never rewritten. Terra remediation documents are
append-only files named `addendum-NNN.md`. Each rejected review is copied into
both `reviews/` and `addenda/` and contains stable `ADD-NNN` findings with:

- one stable `Finding-Key` for the underlying defect;
- the governing specification requirement;
- concrete repository evidence;
- the required correction;
- focused verification.

## Configuration

Copy [examples/project.env.example](examples/project.env.example) and edit the
absolute paths:

```bash
cp examples/project.env.example ~/configs/my-project-light.env
chmod 600 ~/configs/my-project-light.env
```

The essential configuration is:

```bash
export PROJECT="my-project-light"
export REPOSITORY="/path/to/repository"
export SPECIFICATION="/path/to/specification.md"
export DEVELOPMENT_POLICY="path/to/development-policy.txt"
export HARNESS_HOME="/home/user/coding-agent-fs-harness"
export HARNESS_ROOT="/home/user/.local/state/coding-harness-light"

export MANAGER_MODEL="gpt-5.6-terra"
export MANAGER_REASONING_EFFORT="high"
export WORKER_MODEL="gpt-5.6-luna"
export WORKER_REASONING_EFFORT="high"
```

`HARNESS_MAX_MANAGER_REVIEWS=50` is the default emergency cap. It pauses after
that many rejected regular Terra reviews without claiming completion. Set it
to `0` only when you deliberately want an unlimited loop.

`HARNESS_MAX_REPEATED_FINDING_REVIEWS=3` runs a fresh convergence audit when
the same stable finding key appears in three consecutive regular reviews. Set
it to `0` to disable detection. The audit may accept, replace the latest
addendum with an actionable correction, or pause as `NEEDS_OPERATOR`. That last
decision is restricted to incompatible observable requirements or a truly
external secret, permission, service, hardware action, or human choice.

### Optional first-review verification

The manager remains language-neutral by default:

```bash
export HARNESS_MANAGER_REVIEW_CHECKLIST="none"
```

For a C project, enable the comprehensive first-review profile:

```bash
export HARNESS_MANAGER_REVIEW_CHECKLIST="c-strict"
```

The `c-strict` profile tells Terra to run and document:

- the canonical clean build, project tests, and public-interface smoke;
- an optimized C11 build with strict warnings promoted to errors;
- ASan/UBSan builds and execution when supported;
- one already-installed independent analyzer, such as `clang --analyze`,
  `scan-build`, `clang-tidy`, or `cppcheck`, when compatible;
- applicable lexer edge cases, epsilon/nested/ambiguous grammar behavior,
  deterministic termination, and full-input consumption; and
- exit-status and one-line output contracts, including control characters in
  user-provided values.

The complete checklist is appended only to Terra's first review prompt. Later
reviews verify the resulting addenda and focused regressions without
automatically repeating every expensive check. Missing optional analyzer tools
are recorded as skipped and do not cause rejection; the manager never installs
packages. The selected profile is stored in `project.conf`, and the assembled
first-review prompt provides durable evidence of exactly which checklist was
used.

This feature strengthens the manager's review instructions but does not turn
the supervisor into a language-specific test runner. Terra executes and judges
the commands inside its Codex review turn. Projects that require mechanically
mandatory commands should also place those commands in their specification or
provide a dedicated external acceptance gate.

### Codex stall diagnostics

Diagnostics are disabled by default. Enable them temporarily on selected
harnesses while investigating a stuck Codex turn:

```bash
export HARNESS_CODEX_RUST_LOG="codex_core=debug"
export HARNESS_CODEX_STRACE="1"
export HARNESS_CODEX_STRACE_STRING_BYTES="80"
export HARNESS_CODEX_STALL_DIAGNOSTIC_SECONDS="1800"
```

`HARNESS_CODEX_RUST_LOG` is passed to Codex as `RUST_LOG`; non-interactive
Codex diagnostics therefore remain in the turn's existing stderr log.
`HARNESS_CODEX_STRACE=1` starts the complete Node/Codex/code-mode-host process
tree under `strace -ff`. The persistent trace is deliberately limited to
network, process, and signal system calls so long turns do not produce an
unbounded stream of `futex` and `epoll` events. Captured strings are limited by
`HARNESS_CODEX_STRACE_STRING_BYTES`, which defaults to 80.

When a turn produces neither JSONL nor stderr output for
`HARNESS_CODEX_STALL_DIAGNOSTIC_SECONDS`, the executor writes one evidence
snapshot for that quiet interval. If output resumes and a later quiet interval
crosses the threshold, it writes another. Snapshots include:

- the complete descendant process tree and per-thread wait/syscall state;
- file descriptors plus TCP and Unix-domain sockets owned by the tree;
- bounded tails of the turn JSONL and stderr files; and
- when found, a bounded tail of the matching Codex session transcript.

Artifacts are stored beside the turn log in
`logs/<turn>.diagnostics/`, with mode 600 files under the harness's private
state directory. They can contain prompts, source fragments, paths, and other
sensitive debugging context. Review them before sharing. Enabling tracing only
affects new Codex invocations; restart a currently running harness if that turn
must start under `strace`.

The stall snapshot threshold does not terminate or restart Codex. Existing
wall and idle timeout behavior remains controlled separately by
`HARNESS_CODEX_WALL_TIMEOUT_SECONDS` and
`HARNESS_CODEX_IDLE_TIMEOUT_SECONDS`. An idle or wall timeout also captures a
final snapshot before or immediately after termination.

Capture the same snapshot on demand for a currently running turn:

```bash
bin/harness-diagnose ~/configs/my-project-light.env manual
```

The environment file is sourced as trusted Bash. It must be owned by the
current user or root and must not be group/world writable.

## Run

Validate and initialize once. Initialization requires a Git repository with a
valid `HEAD` and no staged, unstaged, or untracked changes:

```bash
bin/harness-check-env ~/configs/my-project-light.env
bin/harness-init ~/configs/my-project-light.env
```

An owner may explicitly accept a dirty starting checkout when necessary:

```bash
bin/harness-init --force ~/configs/my-project-light.env
```

The harness records the launch commit in `project.conf`. Each manager and
worker turn receives the current `HEAD` commit as its canonical diff baseline,
so later owner-created commits on top of the launch commit become baseline
content automatically. Historical or inspected commit hashes mentioned in a
specification are never used to identify worker-authored changes. Codex turns
may edit and delete tracked files when the specification requires it, but may
not move `HEAD`. The executor restores the Git index to its pre-turn state, so
worker edits remain in the working tree without unexpectedly staging them. It
also snapshots and verifies the configured specification, development policy,
immutable inputs, prompts, reviews, addenda, and durable control files around
every turn. If Codex changes protected content, the harness restores it and
rejects the turn.

Start the background supervisor:

```bash
bin/harness-start ~/configs/my-project-light.env
```

Inspect status or follow agent messages:

```bash
bin/harness-status ~/configs/my-project-light.env
bin/harness-watch-agents ~/configs/my-project-light.env
```

Stop and later restart without discarding state:

```bash
bin/harness-stop ~/configs/my-project-light.env
bin/harness-start ~/configs/my-project-light.env
```

State is stored under:

```text
$HARNESS_ROOT/projects/$PROJECT/
├── inputs/
│   ├── specification.txt
│   └── development-policy.txt
├── control/
│   ├── state.env
│   ├── worker-goal.md
│   ├── worker.thread
│   └── final-acceptance.md
├── addenda/
├── reviews/
├── prompts/
├── outputs/
└── logs/
```

`harness-status` reports provider-returned input, cached-input, and output token
totals. Usage is deduplicated by Codex thread so resumed Luna cumulative totals
are not added repeatedly.

## Acceptance behavior

Terra's review output must begin with exactly:

```text
DECISION: ACCEPT
```

or:

```text
DECISION: REVISE
```

An invalid decision or malformed finding protocol is a terminal failure rather
than accidental acceptance. Each ordinary `REVISE` finding must have exactly
one stable `Finding-Key`. `ACCEPT` records `control/final-acceptance.md`;
`REVISE` publishes the next addendum and resumes Luna. A convergence audit uses
`ACCEPT`, `ACTIONABLE`, or `NEEDS_OPERATOR`; only `ACTIONABLE` resumes Luna.
Common Markdown decoration around finding headings, labels, and key values is
normalized before validation and repeated-key comparison; the canonical key
itself must still use only lowercase letters, digits, `.`, `_`, and `-`.

Terra is configured with `workspace-write` by default so it can execute builds
and smoke tests. Its prompt forbids source edits: implementation belongs to
Luna. Use `MANAGER_SANDBOX=read-only` only when the project's verification
commands do not need to create build artifacts.

## Testing the harness

Run the focused integration smoke:

```bash
tests/test-light-harness.sh
```

The test uses a fake Codex executable. It verifies Terra goal creation, a first
Luna implementation, Terra rejection with an addendum, resumption of the same
Luna thread, final Terra acceptance, durable state, and thread-deduplicated
token accounting. It also verifies repeated-finding convergence pausing, the
emergency review cap, and that the strict C checklist is disabled by
default, rejects unsupported profile names, is attached when selected, and is
not repeated after the first review. Diagnostics coverage verifies validated
trace settings, `RUST_LOG` propagation, traced command construction, manual
capture, and automatic capture during a quiet turn. Repository safety coverage
rejects dirty initialization without `--force`, records and injects the
canonical commit baseline despite an older commit named in the specification,
restores protected content and the Git index after an adversarial turn, and
rejects Codex-created commits.

## Benchmarks

The repository includes the complete benchmark specification, deterministic
grader, runner scripts, raw model traces, generated source trees, token
accounting, quality audits, and conclusions under [benchmarks/](benchmarks/).

Start with the [benchmark introduction](benchmarks/README.md), then read the
[single Terra High versus light-harness report](benchmarks/light-vs-single-terra-high.md).

## Known limitations

- This is a prototype harness, not a distributed scheduler.
- A terminal local/process failure requires inspection and a state repair or a
  fresh project ID; only provider quota/transient failures retry automatically.
- Terra is trusted to obey its reviewer-only prompt while using a writable
  sandbox for build commands.
- There is no automatic Git commit, rollback, worktree isolation, or source
  snapshotting.
- Setting the review cap to zero permits unlimited quota consumption if Terra
  and Luna do not converge. The default cap and repeated-finding audit are
  safeguards, not proofs that a task will converge.
- Existing state created by the full harness is not compatible with light
  mode. Use a distinct `HARNESS_ROOT` or `PROJECT`.
