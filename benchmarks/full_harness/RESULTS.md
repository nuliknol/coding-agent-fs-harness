# Terra versus manager/worker benchmark results

Report date: 2026-07-28

Run: `pbnfc-html8-terra-vs-harness-20260727a`

## Executive conclusion

Both competitors completed the same threaded C grammar-compiler and
HTML-like-recognizer assignment and passed all 12 external grader checks.

The single Terra High run was the clear winner for latency and token-price
efficiency:

- 9 minutes 11 seconds instead of 2 hours 14 minutes 15 seconds;
- $0.8631 instead of $13.4679 at the supplied token rates; and
- one model turn instead of 81 manager/worker turns.

The manager/worker harness produced the stronger software artifact. Its result
was conventionally formatted, modular, extensively tested, sanitizer-clean,
and more disciplined about chart deduplication. The single result is best
classified as a successful compact prototype: it passes the external contract,
but has an optimized-build warning, a UBSan finding, very limited project
tests, and an inefficient chart merge for ambiguous grammars.

For this bounded greenfield project, the current fine-grained harness is not
the best way to maximize completed coding per quota. A likely better compromise
is one goal-style Terra High implementation turn followed by one independent
review/fix turn with explicit modularity, sanitizer, and focused-test
requirements.

## Experiment configuration

The competitors started concurrently from fresh copies of the same project:

| Competitor | Configuration |
|---|---|
| Single | `gpt-5.6-terra`, reasoning effort `high`, one persistent completion prompt |
| Harness | Manager `gpt-5.6-terra/high`; worker `gpt-5.6-luna/high` |

The project required an ISO C11 BNF grammar compiler and hierarchical
HTML-like recognizer with a persistent pool of exactly eight POSIX threads,
parallel chart closure and scanning, deterministic merging, diagnostics,
statistics, documentation, and tests. The harness was required to execute ten
independently verifiable plan items. No Oracle was used by either competitor.

Both runner processes exited successfully:

| Competitor | Exit status | Wall seconds |
|---|---:|---:|
| Single Terra High | 0 | 551 |
| Terra manager + Luna workers | 0 | 8,055 |

## Functional result

Both repositories independently passed the same 12/12 external grader:

1. strict pthread build;
2. requested link recognition;
3. nested attributes;
4. deep hierarchy;
5. mismatched-tag rejection;
6. unquoted-attribute rejection;
7. unknown-tag rejection;
8. undefined-symbol rejection;
9. indirect-left-recursion rejection;
10. eight-worker stress behavior;
11. deterministic merge behavior; and
12. the repository's own test suite.

This establishes equal behavior against the benchmark's defined acceptance
surface. It does not, by itself, establish equal maintainability or robustness.

## Latency, tokens, and implementation size

| Metric | Single Terra High | Terra manager + Luna workers | Harness/single |
|---|---:|---:|---:|
| Functional score | 12/12 | 12/12 | tie |
| Wall time | 551 s | 8,055 s | 14.62x |
| Completed model turns | 1 | 81 | 81x |
| Input tokens, including cache reads | 1,370,667 | 41,023,421 | 29.93x |
| Cached-input reads | 1,317,120 | 39,280,640 | 29.82x |
| Uncached input | 53,547 | 1,742,781 | 32.55x |
| Output tokens | 26,662 | 363,966 | 13.65x |
| C/header physical lines | 190 | 3,851 | 20.27x |

The harness total consists of:

| Role | Threads | Input | Cached input | Uncached input | Output |
|---|---:|---:|---:|---:|---:|
| Terra manager | 1 resumed thread, 50 completed turns | 28,128,671 | 27,630,848 | 497,823 | 80,215 |
| Luna workers | 31 worker threads/turns | 12,894,750 | 11,649,792 | 1,244,958 | 283,751 |
| Combined harness | 32 threads, 81 turns | 41,023,421 | 39,280,640 | 1,742,781 | 363,966 |

The ten requested harness plan items expanded into 31 worker leaf executions
and 50 manager planning/review turns. That orchestration and repeated context
processing is the main source of the cost difference. The Terra manager alone
processed substantially more input than the entire single-agent run, so the
lower Luna rate could not offset the orchestration overhead.

### Token-accounting correction

Codex reports cumulative usage for a resumed thread. The first generated report
incorrectly added every cumulative manager snapshot and overstated harness
input as approximately 585 million tokens. The evaluator was corrected to
group records by Codex `thread_id`, take the maximum cumulative usage for each
thread, and then sum distinct threads. All figures in this report use the
corrected 41,023,421-token harness total.

## Token-price-equivalent cost

The supplied prices, in USD per million tokens, were:

| Model | Uncached input | Cache read | Cache write | Output |
|---|---:|---:|---:|---:|
| `gpt-5.6-terra` | $2.50 | $0.25 | $3.125 | $15.00 |
| `gpt-5.6-luna` | $1.00 | $0.10 | $1.25 | $6.00 |

The Codex usage records explicitly reported zero cache-write tokens, so no
cache-write charge was needed. The formula was:

```text
cost = (uncached_input * input_rate
        + cached_input * cache_read_rate
        + output * output_rate) / 1,000,000
```

| Component | Uncached input | Cache reads | Output | Total |
|---|---:|---:|---:|---:|
| Single Terra High | $0.1338675 | $0.3292800 | $0.3999300 | **$0.8630775** |
| Harness Terra manager | $1.2445575 | $6.9077120 | $1.2032250 | **$9.3554945** |
| Harness Luna workers | $1.2449580 | $1.1649792 | $1.7025060 | **$4.1124432** |
| Complete harness | $2.4895155 | $8.0726912 | $2.9057310 | **$13.4679377** |

At these rates, the harness cost $12.6048602 more and was 15.6046 times as
expensive as the single Terra run for the same 12/12 external score.

The benchmark used ChatGPT authentication. These values are therefore
API-price equivalents calculated from the supplied rates, not an itemized
subscription charge.

## Engineering-quality assessment

### Structure and maintainability

| Measure | Single Terra | Manager/worker |
|---|---:|---:|
| C/header files | 6 | 15 |
| C/header physical lines | 190 | 3,851 |
| Project test files | 5 | 12 |
| Project test lines | 30 | 1,999 |
| README lines | 30 | 159 |
| Longest C/header source line | 1,426 characters | 88 characters |

The single result is extremely compressed. Several functions contain many
statements and branches on one physical line, which makes review, debugging,
and future changes difficult. The harness result separates diagnostics,
grammar lexing and AST handling, markup lexing, chart storage, worker-pool
management, and recognition behind dedicated headers and source modules.

The harness is much larger and carries more code surface, so line count is not
itself a quality score. Its advantage comes from conventional formatting,
clear module boundaries, focused interfaces, documentation, and tests.

### Test coverage

Both test suites were rebuilt with GCC coverage instrumentation and executed:

| Coverage observation | Single Terra | Manager/worker |
|---|---:|---:|
| Executable source lines | 102 | 1,836 |
| Lines executed | about 99 (97.06%) | about 1,542 (83.99%) |
| Branch outcomes taken at least once | about 69% | about 70% |

The single tree's high line percentage is inflated by compressed source lines:
one executed physical line can contain many independent branches and
statements. The branch percentages are similar, while the harness tests
exercise substantially more distinct code and target individual subsystems.

### Sanitizer and optimized-warning audit

The harness repository passed its complete 12-test project suite when rebuilt
with:

```text
-O1 -g -Wall -Wextra -Werror -pedantic -pthread
-fsanitize=address,undefined -fno-omit-frame-pointer
```

The single repository did not pass the same strict audit:

1. At `-O1 -Werror`, GCC rejected `grammar_load()` because the `start` pointer
   may be used uninitialized on an error path.
2. After removing `-Werror` to allow execution, UBSan reported a null pointer
   passed as the base argument to `qsort()` when the candidate count was zero.

The ordinary benchmark build and external grader still pass. These findings
show that the single result meets the visible functional contract but needs
hardening before it should be treated as production-quality C.

### Chart deduplication and ambiguity probe

Both competitors implemented a real persistent eight-thread worker pool. The
single implementation did not fake the concurrency requirement.

Their merge semantics differ:

- The single implementation sorts and deduplicates candidates generated in
  the current worker batch, then appends them to the destination chart without
  checking whether the chart already contains the same item.
- The harness implementation deduplicates the current batch and inserts
  through a chart API that also rejects items already present in the chart.

An additional valid, acyclic, ambiguous epsilon grammar was used to exercise
multiple derivation paths to identical chart items. Both implementations
accepted it, but their work differed:

| Ambiguity probe | Single Terra | Manager/worker |
|---|---:|---:|
| Recognition rounds | 75 | 28 |
| Total reported worker tasks | 1,236 | 96 |

This confirms that the single merge weakness is observable as duplicate work,
not merely a stylistic concern. The harness chart has the stronger fixed-point
and deduplication behavior.

After the audit, both repositories were restored to their ordinary build
configuration and rechecked against the external grader; both remained 12/12.

## Overall interpretation

### What the single run demonstrated

One carefully prompted Terra High agent can implement a novel threaded C
project rapidly and cheaply when the specification and deterministic acceptance
tests are precise. It produced a genuine working implementation rather than a
stub or hard-coded grader solution.

Its weak points are code compression, shallow local testing, an optimized
compiler warning, a UBSan finding, and weaker chart deduplication. It is an
excellent prototype, but it needs a cleanup and hardening pass.

### What the harness demonstrated

The manager/worker process produced a more maintainable and robust artifact:
modular code, focused subsystem tests, stronger documentation, sanitizer-clean
execution, and better chart semantics.

The cost was excessive for the observed gain. Eighty-one model turns and
fine-grained review boundaries consumed about 15.6 times the token-price
equivalent and 14.6 times the wall time. The external functional score was
unchanged.

### Recommended operating strategy

For the goal of maximizing useful coding per quota:

1. Default to a single Terra High goal-style implementation for cohesive,
   well-specified features with an authoritative test loop.
2. Explicitly require conventional formatting, modularity, focused unit tests,
   optimized `-Werror`, ASan, and UBSan in the implementation prompt.
3. Add one independent review/fix turn for durable code rather than using a
   manager review after every small leaf.
4. Reserve the full manager/worker harness for projects where work must survive
   context boundaries, multiple subsystems need independent ownership, or
   recovery and auditability justify the overhead.
5. If using the harness, reduce ten fine-grained roots to approximately three
   or four coarse phases and review at phase boundaries.
6. Keep Oracle disabled during ordinary implementation and use at most one
   final acceptance audit when the extra assurance is worth its cost.

## Limitations

- This is one project and one run per competitor, not a statistically powered
  model comparison.
- Both competitors knew the public specification and were evaluated with one
  deterministic external grader.
- The competitors ran concurrently on the same account and host, so resource
  contention may affect wall time.
- The harness was deliberately required to use ten independently verifiable
  tasks, while the single agent was allowed one uninterrupted turn. This is the
  real process comparison requested, but it also explains much of the overhead.
- The sanitizer, coverage, and ambiguity probe were post-run quality audits,
  not preregistered acceptance criteria.
- Physical lines of code measure implementation size, not delivered quality.
- ChatGPT quota accounting may not equal the supplied per-token API rates.

The result is strong evidence about this harness configuration on bounded
greenfield work, but it does not establish that a single Terra run will beat a
manager/worker process on every long-running or integration-heavy assignment.

## Saved artifacts

- Machine-readable comparison:
  [`runs/pbnfc-html8-terra-vs-harness-20260727a/comparison.tsv`](runs/pbnfc-html8-terra-vs-harness-20260727a/comparison.tsv)
- Generated comparison:
  [`runs/pbnfc-html8-terra-vs-harness-20260727a/comparison.md`](runs/pbnfc-html8-terra-vs-harness-20260727a/comparison.md)
- Machine-readable quality audit:
  [`runs/pbnfc-html8-terra-vs-harness-20260727a/quality-audit.tsv`](runs/pbnfc-html8-terra-vs-harness-20260727a/quality-audit.tsv)
- Single grader output:
  [`runs/pbnfc-html8-terra-vs-harness-20260727a/single/grader.out`](runs/pbnfc-html8-terra-vs-harness-20260727a/single/grader.out)
- Manager/worker grader output:
  [`runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/grader.out`](runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/grader.out)
- Supplied pricing recorded for the run:
  [`runs/pbnfc-html8-terra-vs-harness-20260727a/pricing.env`](runs/pbnfc-html8-terra-vs-harness-20260727a/pricing.env)
- Corrected evaluator:
  [`evaluate.sh`](evaluate.sh)
