# Light-harness benchmark

This benchmark reruns the exact `pbnfc` assignment used by the archived full
harness benchmark. It compares:

- the completed full harness run
  `pbnfc-html8-terra-vs-harness-20260727a`; and
- one fresh light harness run with Terra High as goal author/reviewer and one
  persistent Luna High worker thread.

The specification, repository guidance, and deterministic 12-check grader are
read directly from `../full_harness/shared` and copied into each run directory.
The light runner does not invoke an Oracle.

The completed comparison and conclusions are in [RESULTS.md](RESULTS.md).
For the public overview and the final single-versus-light conclusion, start at
[../README.md](../README.md).

## Run

```bash
BENCHMARK_CODEX_HOME="$HOME/.codex" \
BENCHMARK_CODEX_BIN=codex \
./benchmarks/light/run.sh
```

Optional overrides:

```bash
BENCHMARK_RUN_ID=my-light-trial \
BENCHMARK_SANDBOX=workspace-write \
BENCHMARK_DEVELOPMENT_POLICY=/path/to/development-policy.txt \
./benchmarks/light/run.sh
```

The run directory is never overwritten. There is no wall-clock or idle
timeout by default so a long autonomous Luna turn can finish naturally.
If no policy override is supplied, the runner uses
[development-policy.txt](development-policy.txt), the same prototype,
feature-first policy used by the archived light run.

## Evaluate

The runner automatically invokes:

```bash
./benchmarks/light/evaluate.sh ./benchmarks/light/runs/RUN_ID
```

The evaluator reruns the external grader and reports functional score, elapsed
time, role/thread counts, manager/worker handoffs, provider-reported token
usage, API-price-equivalent cost, and C/header lines. Resumed Luna usage is
deduplicated by Codex thread ID.

The generated `comparison.md` and `comparison.tsv` compare the fresh light run
with the preserved full-harness baseline. ChatGPT-authenticated runs consume
subscription quota; the dollar figure is an API-price equivalent using the
user-supplied rates, not an itemized invoice.
