# Coding Agent Filesystem Harness — light mode

This branch implements a deliberately small manager/worker loop for prototype,
feature-first development.

One Terra High turn writes a persistent goal for one Luna High coding thread.
Luna works on the complete specification in a long autonomous `codex exec`
turn. Terra then audits the complete repository. If anything is missing, Terra
publishes one exhaustive completion addendum and the harness resumes the same
Luna thread. The loop ends only when Terra accepts the implementation or an
optional operator review limit is reached.

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
| `ACCEPTED` | Terra accepted the complete specification |
| `REVIEW_LIMIT_REACHED` | Optional operator limit paused the loop |
| `TERMINAL_FAILURE` | A non-provider process or protocol error stopped it |

Provider quota and transient failures retry in place. Supervisor restart
preserves the manager goal, Luna thread ID, addenda, review history, token logs,
and repository changes.

The original specification is never rewritten. Terra remediation documents are
append-only files named `addendum-NNN.md`. Each rejected review is copied into
both `reviews/` and `addenda/` and contains stable `ADD-NNN` findings with:

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

`HARNESS_MAX_MANAGER_REVIEWS=0` is the default and means unlimited review
cycles. A positive value pauses after that many rejected Terra reviews. It does
not claim that the project is complete.

The environment file is sourced as trusted Bash. It must be owned by the
current user or root and must not be group/world writable.

## Run

Validate and initialize once:

```bash
bin/harness-check-env ~/configs/my-project-light.env
bin/harness-init ~/configs/my-project-light.env
```

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

An invalid decision is a terminal protocol failure rather than accidental
acceptance. `ACCEPT` records `control/final-acceptance.md`; `REVISE` publishes
the next addendum and resumes Luna.

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
token accounting.

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
- Unlimited review cycles can consume unlimited quota if Terra and Luna do not
  converge. Set a positive review limit when a cost ceiling matters.
- Existing state created by the full harness is not compatible with light
  mode. Use a distinct `HARNESS_ROOT` or `PROJECT`.
