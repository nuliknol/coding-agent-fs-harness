# Manager/worker versus single-agent benchmark

The completed Terra-versus-manager/worker trial, including functional,
token-cost, sanitizer, coverage, quality, and final conclusions, is documented
in [RESULTS.md](RESULTS.md). Start with the public benchmark index at
[../README.md](../README.md).

This benchmark compares two ways of implementing the same small C project:

1. one `gpt-5.6-terra` / `high` Codex process; and
2. this harness with `gpt-5.6-terra` / `high` as manager and
   `gpt-5.6-luna` / `high` as worker.

The project is an eight-thread BNF grammar compiler and hierarchical HTML-like
recognizer. It needs two lexers, grammar validation, a general chart recognizer,
a persistent POSIX thread pool, parallel closure/scanning rounds, thread-local
candidate buffers, deterministic merging, diagnostics, concurrency statistics,
and stress tests. The specification requires ten independently verifiable
manager tasks. Neither side receives an Oracle audit.

## Run

Use the same authenticated Codex home for both competitors. The run launches
the competitors concurrently and writes all generated state below
`benchmarks/full_harness/runs/<run-id>`.

The unified source tree contains the manager and worker supervisors. The runner
selects `HARNESS_MODE=full` and enables v2 proactive decomposition; the Light
runner selects `HARNESS_MODE=light`.

```bash
export BENCHMARK_CODEX_HOME=/path/to/your/authenticated/codex-home
./benchmarks/full_harness/run.sh
```

Optional environment overrides:

```bash
BENCHMARK_RUN_ID=trial-01 \
BENCHMARK_CODEX_BIN=codex \
BENCHMARK_SANDBOX=workspace-write \
./benchmarks/full_harness/run.sh
```

The run deliberately fails rather than overwriting an existing run directory.
It has no timeout: a quota wait or a long coding turn is recorded as part of the
observed latency. Interrupting it preserves both workspaces and logs; rerun:

```bash
./benchmarks/full_harness/evaluate.sh \
  ./benchmarks/full_harness/runs/<run-id>
```

to score whatever was completed.

## Measurements

`evaluate.sh` runs the same black-box grader against both repositories and
produces `comparison.md` and `comparison.tsv`:

- wall-clock latency;
- completed Codex turns, and manager/worker switches;
- input and output tokens reported in Codex JSONL events (when the provider
  exposes them);
- cached-input tokens and an optional API-dollar estimate, using rates supplied
  in the run's `pricing.env`;
- C and header lines under `src/` and `include/`;
- independent build and behavioral checks.

The functional score is primary. Lines of code and raw tokens are diagnostic
metrics, not quality metrics.  A benchmark result is useful only when both
competitors are run from fresh repositories and against the same harness
revision, Codex account, and model settings.

If the run is authenticated with ChatGPT, its cost is credits/usage limits from
the subscription, not a per-token API invoice.  `estimated_api_usd` therefore
stays `n/a`.  For API-key runs, copy current official per-million-token rates
into the generated `pricing.env` (seeded from `pricing.env.example`) before
scoring; the report will calculate the estimate separately for Terra and Luna.

The harness side may create revisions after a failed task.  That is intentional:
the comparison measures the real cost of obtaining a working result, rather than
pretending a failed first attempt completed the project.
