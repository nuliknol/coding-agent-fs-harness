# Light harness versus single Terra High

Report date: 2026-07-28

The two configurations compared here are:

- **Single Terra High:** one standalone Terra High agent implements the entire
  specification without a separate reviewer.
- **Light harness:** a Luna High worker implements the specification, then a
  separate Terra High manager audits Luna's result and sends corrective
  addenda until it accepts the implementation.

## Executive conclusion

Single Terra High is much cheaper and faster, but the light harness produced
materially better code.

| Metric | Single Terra High | Light harness |
|---|---:|---:|
| API-price-equivalent cost | **$0.863078** | **$3.296026** |
| Runtime | 9m 11s | 45m 16s |
| Model turns | 1 | 13 |
| Total input tokens | 1,370,667 | 9,337,500 |
| Uncached input tokens | 53,547 | 504,220 |
| Output tokens | 26,662 | 120,848 |
| C/header physical lines | 190 | 1,710 |
| Public grader | 12/12 | 12/12 |

The light harness costs **3.82 times more** and takes **4.93 times longer**.
Single Terra saves approximately **$2.43**, or **73.81%** of the light
harness's cost.

The costs use the supplied per-million-token prices and are API-price
equivalents, not an itemized ChatGPT invoice.

## Cost per final code line

Using final C/header physical lines as the code-line count:

```text
Single Terra: $0.863078 / 190 lines   = $0.004542516 per line
Light:        $3.296026 / 1,710 lines = $0.001927501 per line
```

| Measure | Single Terra High | Light harness |
|---|---:|---:|
| Final C/header lines | 190 | 1,710 |
| Total cost equivalent | $0.863078 | $3.296026 |
| Cost per final line | **$0.004543** | **$0.001928** |
| Final lines per dollar | 220.14 | 518.81 |

By this measure, the light harness generated final code at **57.57% lower cost
per physical line**, or **2.36 times as many final lines per dollar**.

Physical LOC is only a productivity proxy, not a quality-adjusted unit. The
single-Terra artifact contains a 1,426-character source line and compresses much
more behavior onto each physical line. Conversely, more light-harness lines can
also represent verbosity rather than useful functionality. The functional and
quality probes below should therefore be considered alongside this ratio.

## Quality comparison

Passing the public grader did not mean that the two artifacts had equal
quality. Direct probes found real defects in the single-Terra result that the
light harness repaired:

| Probe | Single Terra High | Light harness |
|---|---|---|
| Public 12-case grader | pass | pass |
| Nested epsilon grammar | hangs beyond 10 seconds | accepts immediately |
| Empty-string terminal semantics | incorrectly rejects | accepts |
| Newline-bearing rejection diagnostic | produces multiple lines | produces one line |
| Newline-bearing path/start diagnostic | produces multiple lines | produces one line |
| 13-level ambiguity fixed point | 75 rounds / 1,236 tasks | 28 rounds / 99 tasks |
| Optimized ASan/UBSan audit | null-`qsort()` UB | null-`qsort()` UB |

The single-Terra implementation is extremely compressed: 190 C/header lines,
including a 1,426-character source line. The light implementation has 1,710
conventionally formatted lines separated into lexer, grammar compiler,
diagnostics, worker-pool, recognizer, and CLI modules. It is substantially
easier to inspect, debug, and extend.

Both implementations still contain the same sanitizer-visible zero-candidate
`qsort()` defect. The light result is therefore a materially more complete and
maintainable prototype, but it is not production-clean.

## Observed completeness

Completeness depends on which verified checks form the denominator. The public
grader alone cannot distinguish the artifacts because both pass all 12 cases.
Adding the eight independently reviewed specification cases exposes a material
difference:

| Completeness measure | Single Terra High | Light Worker–Manager |
|---|---:|---:|
| Public grader only | 12/12 = **100%** | 12/12 = **100%** |
| Public grader + 8 reviewed specification cases | 15/20 = **75%** | 20/20 = **100%** |
| Including sanitizer robustness check | 15/21 = **71.4%** | 20/21 = **95.2%** |

The eight additional specification cases covered:

1. complete indirect left-recursion detection beyond 256 rules;
2. punctuation versus `$IDENT` token classification;
3. maximal outside-tag text runs;
4. unprocessed chart ranges, deduplication, and actual task accounting;
5. already-completed epsilon constituent closure;
6. empty terminal and empty quoted-string handling;
7. one-line rejection diagnostics; and
8. one-line command-line grammar diagnostics.

The standalone Terra artifact passed the first three additional cases and
failed the remaining five. The final light artifact passed all eight after its
Terra manager identified defects and directed its Luna worker to repair them.
Both artifacts failed the subsequent sanitizer check.

On this benchmark, the best quality-adjusted summary is therefore:

- **Light harness:** 95.2% observed completeness.
- **Single Terra High:** 71.4% observed completeness.
- **Difference:** 23.8 percentage points in favor of light.

If sanitizer robustness is excluded and only verified functional specification
checks are counted, the corresponding result is 100% for light and 75% for
single Terra.

These percentages are a transparent benchmark index, not proof of absolute
whole-specification completeness. The checks are equally weighted, and the
eight reviewed cases were discovered through audit rather than sampled
randomly. A true whole-specification percentage would require converting every
normative specification statement into a traceability matrix and verifying
each one.

## Recommendation

- If the only objective is to pass the visible grader at minimum cost, use a
  single Terra High run.
- If the objective is a maintainable prototype that more closely implements
  the entire specification, the light harness provides the stronger result at
  a 3.82-times cost premium.
- The light harness remains a much more quota-efficient compromise than the
  full harness: $3.2960 versus $13.4679 in this benchmark.

The harness now offers this optimization as the opt-in
`HARNESS_MANAGER_REVIEW_CHECKLIST=c-strict` profile. It gives the light
harness's Terra manager a fixed first-review checklist covering optimized
`-Werror`, ASan/UBSan, optional installed static analyzers, lexer edge cases,
epsilon/ambiguity behavior, and one-line output contracts. It is intended to
batch more findings into fewer review cycles. The profile was implemented after
this benchmark and was not enabled for the measured run, so it does not alter
the results above.

## Final decision

For the stated objective of maximizing useful, maintainable coding work per
quota, **the light harness is the preferred default development mode** in this
benchmark.

This conclusion rests on two results:

1. The light harness produced higher-quality code. Luna created that
   implementation, and the light harness's separate Terra manager found
   specification failures and directed Luna to repair them. Those failures
   remained in the artifact produced by the standalone Terra agent. The final
   light artifact is also substantially more modular and maintainable.
2. Its nominal code-generation cost was lower: $0.001928 per final C/header
   physical line versus $0.004543 for single Terra, equivalent to 2.36 times as
   many final physical lines per dollar.

The conclusion does not mean that light is cheaper per assignment. It cost
$3.2960 in total, 3.82 times the single run's $0.8631. Nor is physical LOC a
quality-adjusted unit; compressed or verbose formatting can distort it. The
more persuasive evidence is the combination of lower nominal line cost with
demonstrably better specification compliance and maintainability.

The resulting operating choice is:

- **Single Terra High** for the cheapest visible-test pass.
- **Light harness** for the best observed balance of quality, maintainability,
  and coding output per quota.
- **Full harness** only when its additional robustness justifies its much
  higher cost.

## Detailed results

The complete experimental report and raw data remain available at:

- [`light/RESULTS.md`](light/RESULTS.md)
- [`light/runs/pbnfc-html8-light-20260728a/single-vs-light.tsv`](light/runs/pbnfc-html8-light-20260728a/single-vs-light.tsv)
