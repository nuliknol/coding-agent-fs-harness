# Full harness versus light harness benchmark results

Report date: 2026-07-28

Light run: `pbnfc-html8-light-20260728a`

Full baseline: `pbnfc-html8-terra-vs-harness-20260727a`

## Executive conclusion

The light harness is a substantial quota-efficiency improvement over the full
harness on this assignment. Both results pass the same 12/12 external grader,
but the light run used:

- 13 model turns instead of 81;
- 9.34 million input tokens instead of 41.02 million;
- 120,848 output tokens instead of 363,966;
- 45 minutes 16 seconds instead of 2 hours 14 minutes 15 seconds; and
- $3.2960 instead of $13.4679 in API-price-equivalent token cost.

That is a **75.53% cost reduction**, a **77.24% input-token reduction**, and a
**66.28% wall-time reduction** relative to the full harness.

The quality result is mixed. The light artifact is modular, conventionally
formatted, leak-free in a Valgrind smoke run, and handles the same ambiguity
probe in the same 28 recognition rounds. Its strict optimized ASan/UBSan test
does, however, find a null base passed to `qsort()` when there are zero
candidates. The full-harness artifact passed the equivalent sanitizer audit and
has broader tests and higher coverage.

The light harness therefore achieved the intended compromise: far more
quota-efficient than the full harness and much stronger than an unchecked
single worker delivery, but not equal to the full harness's post-run robustness.

## Experimental controls

The light run copied the archived full benchmark inputs. Both specification
files have SHA-256:

```text
86d2588cb2631957e68cc2629e64d4f31e5a55e398e90d71fbef50679af8c6ae
```

Both harnesses used:

| Role | Model | Reasoning |
|---|---|---|
| Manager | `gpt-5.6-terra` | high |
| Worker | `gpt-5.6-luna` | high |

Neither benchmark used an Oracle. The light run used one persistent Luna thread
and fresh Terra goal/review turns. The full result is the preserved earlier run,
not a simultaneous rerun, so model stochasticity and machine/account conditions
remain limitations.

## Quota and latency comparison

| Metric | Full harness | Light harness | Light/full |
|---|---:|---:|---:|
| Functional score | 12/12 | 12/12 | tie |
| Wall time | 8,055 s | 2,716 s | 0.3372x |
| Completed turns | 81 | 13 | 0.1605x |
| Recorded handoffs/switches | 81 | 12 | 0.1481x |
| Input tokens, including cache | 41,023,421 | 9,337,500 | 0.2276x |
| Cached-input reads | 39,280,640 | 8,833,280 | 0.2249x |
| Uncached input | 1,742,781 | 504,220 | 0.2893x |
| Output tokens | 363,966 | 120,848 | 0.3320x |
| API-price-equivalent cost | $13.467938 | $3.296026 | 0.2447x |
| C/header physical lines | 3,851 | 1,710 | 0.4440x |

The supplied prices were:

| Model | Uncached input / M | Cache read / M | Output / M |
|---|---:|---:|---:|
| Terra | $2.50 | $0.25 | $15.00 |
| Luna | $1.00 | $0.10 | $6.00 |

The calculation is:

```text
cost = (uncached_input * input_rate
        + cached_input * cache_read_rate
        + output * output_rate) / 1,000,000
```

These are API-price equivalents. The run used ChatGPT authentication, so they
are not an itemized invoice.

## Light-harness role breakdown

| Role | Turns | Input | Cached | Uncached | Output | Cost equivalent |
|---|---:|---:|---:|---:|---:|---:|
| Terra manager | 7 | 2,131,741 | 1,840,896 | 290,845 | 52,332 | $1.972317 |
| Luna worker | 6 | 7,205,759 | 6,992,384 | 213,375 | 68,516 | $1.323709 |
| Combined | 13 | 9,337,500 | 8,833,280 | 504,220 | 120,848 | **$3.296026** |

Terra generated the persistent goal, then performed six reviews. Luna performed
one long implementation turn and five resumed remediation turns. Resumed Luna
usage is cumulative, so accounting groups JSONL records by thread ID and uses
the maximum cumulative value rather than summing each snapshot.

Although Luna processed most tokens, Terra accounted for about 60% of the
price-equivalent cost. Fresh strict reviews are now the main optimization target.

## What the review loop accomplished

Luna's first autonomous turn implemented the complete project, debugged its
parallel recognizer, and independently reached 12/12 in about 17 minutes. Terra
then found specification defects beyond the public grader:

1. incomplete left-recursion detection beyond 256 rules;
2. punctuation incorrectly matching `$IDENT`;
3. incorrect maximal outside-tag text runs;
4. closure redispatching processed chart items and synthetic task counts;
5. missed already-completed epsilon constituents;
6. uninitialized empty-terminal and empty-string buffers;
7. multi-line rejection details from control characters; and
8. multi-line command-line diagnostics from newline-bearing arguments.

These became five exhaustive addenda and five resumed Luna correction turns.
Terra accepted the sixth review.

This validates the light architecture: Luna retained the entire implementation
context, while Terra intervened only at full-repository acceptance boundaries.
It also shows why setting a very low manager-review cap would have reduced cost
at the expense of real correctness—review three still found the epsilon closure
bug, and later reviews found C and output-contract issues.

## Engineering-quality comparison

| Measure | Full harness | Light harness |
|---|---:|---:|
| C/header files | 15 | 11 |
| C/header physical lines | 3,851 | 1,710 |
| Project test files | 12 | 10 |
| Project test physical lines | 1,999 | 100 |
| README physical lines | 159 | 83 |
| Longest C/header line | 88 | 114 |
| Coverage executable lines | 1,836 | 1,063 |
| Coverage line percentage | 83.99% | 74.04% |
| Branch outcomes taken | about 70% | about 69.76% |

The light artifact is not compressed or monolithic. It separates the CLI,
diagnostics, grammar compiler, markup lexer, persistent worker pool, and
recognizer across six source modules and five public/internal headers. Its
smaller test suite matches the configured prototype/feature-first development
policy; the full harness produced substantially more test and source surface.

### Sanitizer and memory audit

The light tree compiles successfully at `-O1 -Werror` with ASan and UBSan, but
`make test` reports:

```text
src/recognizer.c:215:9: runtime error:
null pointer passed as argument 2, which is declared to never be null
```

This occurs when `qsort()` is called with a null base and a zero candidate
count. The normal strict build and 12/12 grader still pass. A normal-build
Valgrind smoke reports 274 allocations, 274 frees, zero bytes remaining, and
zero errors.

The benchmark artifact was deliberately not repaired after acceptance; changing
it would invalidate the measured model result.

### Coverage

After running both `make test` and the external grader under GCC coverage:

- 787 of 1,063 executable source lines were exercised (74.04%);
- approximately 69.76% of branch outcomes were taken at least once.

The full harness covered 83.99% of 1,836 executable lines with approximately
70% of branch outcomes. Branch coverage is nearly equal; the full tree exercises
more code and has broader line coverage.

### Exact ambiguity probe

The same 13-level acyclic diamond/epsilon grammar used in the original quality
audit was rerun:

| Measure | Full harness | Light harness | Single Terra |
|---|---:|---:|---:|
| Recognition | accept | accept | accept |
| Rounds | 28 | 28 | 75 |
| Summed worker task counts | 96 | 99 | 1,236 |

The light result therefore has fixed-point behavior comparable to the full
artifact on this probe. Its task counts reflect the later correction to count
actual assignments rather than simply copying pool generations.

## Direct comparison with single Terra High

The single Terra run remains the cost and latency winner by a wide margin:

| Metric | Single Terra High | Light harness | Light/single |
|---|---:|---:|---:|
| Functional grader | 12/12 | 12/12 | tie |
| Wall time | 551 s | 2,716 s | 4.9292x |
| Model turns | 1 | 13 | 13.0000x |
| Input tokens, including cache | 1,370,667 | 9,337,500 | 6.8124x |
| Cached-input reads | 1,317,120 | 8,833,280 | 6.7065x |
| Uncached input | 53,547 | 504,220 | 9.4164x |
| Output tokens | 26,662 | 120,848 | 4.5326x |
| API-price-equivalent cost | **$0.863078** | **$3.296026** | **3.8189x** |
| C/header physical lines | 190 | 1,710 | 9.0000x |

Single Terra saved $2.432948, or 73.81% of the light harness's cost. This is
not, however, an equal-quality tie hidden behind different code sizes. Direct
post-run probes exposed specification failures in the single artifact that the
Terra/Luna review loop repaired:

Dividing each run's cost by its final C/header physical lines gives:

| Cost-density measure | Single Terra High | Light harness |
|---|---:|---:|
| Cost per final physical line | **$0.004542516** | **$0.001927501** |
| Final physical lines per dollar | 220.14 | 518.81 |

Light therefore has a 57.57% lower nominal cost per final code line and produces
2.36 times as many physical lines per dollar. This is not a quality-adjusted
productivity measure: the single artifact's 1,426-character source line makes
physical LOC especially non-equivalent, while additional lines can also
represent verbosity rather than functionality.

| Probe | Single Terra High | Light harness |
|---|---|---|
| Public 12-case grader | pass | pass |
| Punctuation must not match `$IDENT` | pass | pass |
| Maximal outside-tag text run | pass | pass |
| Nested nullable-symbol closure on empty input | **hangs beyond 10 s** | accepts immediately |
| Empty string terminal/attribute semantics | **incorrect reject** | accepts |
| One-line rejection with newline-bearing terminal | **multi-line output** | one line |
| One-line grammar error with newline-bearing path/start | **multi-line output** | one line |
| 257-rule left-recursion cycle | rejects correctly | rejects correctly |
| Optimized ASan/UBSan audit | **null-`qsort()` UB** | **null-`qsort()` UB** |
| 13-level ambiguity fixed point | 75 rounds / 1,236 tasks | 28 rounds / 99 tasks |

The single implementation is also extremely compressed: 190 C/header physical
lines, including a 1,426-character source line, versus 1,710 conventionally
formatted lines split into lexer, grammar compiler, diagnostics, worker-pool,
recognizer, and CLI modules. Its nominal 97.06% line coverage covers only 102
executable physical lines and is inflated by that compression, so it should not
be read as better behavioral coverage than light's 74.04% of 1,063 executable
lines.

Both artifacts still share the zero-candidate `qsort()` sanitizer defect. The
light harness therefore produced a materially more complete and maintainable
prototype, not a production-clean implementation.

### Observed completeness

Using the 12 public-grader cases plus the eight independently reviewed
specification cases as an equally weighted functional index, single Terra
passes 15/20 (**75%**) and light passes 20/20 (**100%**). Adding the shared
sanitizer robustness check changes the observed totals to:

| Artifact | Checks passed | Observed completeness |
|---|---:|---:|
| Single Terra High | 15/21 | **71.4%** |
| Light Worker–Manager | 20/21 | **95.2%** |

The resulting gap is 23.8 percentage points in favor of light. This is a
benchmark-observed index, not an absolute whole-specification percentage; a
true whole-spec measurement would require an exhaustive traceability matrix
for every normative requirement.

## Interpretation

For the user's goal—more completed coding per quota—the light harness is clearly
better than the full fine-grained harness on this project:

- it preserved independent management and iterative correction;
- it reduced cost by roughly fourfold;
- it reduced elapsed time by roughly threefold;
- it still discovered and repaired eight nontrivial specification gaps.

It is not the cheapest possible path. The single Terra High run cost $0.8631
and took 551 seconds, versus $3.2960 and 2,716 seconds for light. If the only
criterion is passing the visible grader at minimum cost, single Terra wins.
If the criterion is a maintainable prototype that more closely implements the
whole specification, light is the stronger result: its reviews found real
failures that remain reproducible in the single artifact. Light provides that
correctness/maintainability improvement while remaining far below full-harness
cost.

The most useful next optimization is not more worker fragmentation. An opt-in
implementation is now available as
`HARNESS_MANAGER_REVIEW_CHECKLIST=c-strict`: it adds a comprehensive first
Terra review covering optimized `-Werror`, ASan/UBSan, optional installed
static analyzers, lexer edge cases, epsilon/ambiguity, and output-line
contracts. It was added after this measured run and therefore does not change
the benchmark result.

## Artifacts

- Machine-readable quota comparison:
  [`runs/pbnfc-html8-light-20260728a/comparison.tsv`](runs/pbnfc-html8-light-20260728a/comparison.tsv)
- Per-role usage:
  [`runs/pbnfc-html8-light-20260728a/role-usage.tsv`](runs/pbnfc-html8-light-20260728a/role-usage.tsv)
- Machine-readable quality audit:
  [`runs/pbnfc-html8-light-20260728a/quality-audit.tsv`](runs/pbnfc-html8-light-20260728a/quality-audit.tsv)
- Machine-readable single-versus-light comparison:
  [`runs/pbnfc-html8-light-20260728a/single-vs-light.tsv`](runs/pbnfc-html8-light-20260728a/single-vs-light.tsv)
- External grader output:
  [`runs/pbnfc-html8-light-20260728a/grader.out`](runs/pbnfc-html8-light-20260728a/grader.out)
- Terra's final acceptance:
  [`runs/pbnfc-html8-light-20260728a/state/projects/benchmark-light-pbnfc-html8-light-20260728a/control/final-acceptance.md`](runs/pbnfc-html8-light-20260728a/state/projects/benchmark-light-pbnfc-html8-light-20260728a/control/final-acceptance.md)
- Post-run quality logs:
  [`runs/pbnfc-html8-light-20260728a/quality/`](runs/pbnfc-html8-light-20260728a/quality/)
