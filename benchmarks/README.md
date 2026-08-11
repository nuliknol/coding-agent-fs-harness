# Coding harness benchmarks

This directory contains the reproducible inputs, runners, preserved model
traces, generated repositories, measurements, and reports used to compare three
ways of completing the same nontrivial C assignment:

1. one standalone Terra High agent;
2. the original fine-grained full harness with a Terra High manager and Luna
   High workers; and
3. the light harness with a Terra High goal author/reviewer and one persistent
   Luna High worker thread.

No configuration used an Oracle. The purpose was to measure how orchestration
changes functional completeness, maintainability, elapsed time, token usage,
and API-price-equivalent cost.

## Start here

- [Final single Terra High versus light-harness report](light-vs-single-terra-high.md)
- [Light versus full-harness results](light/RESULTS.md)
- [Single Terra High versus full-harness results](full_harness/RESULTS.md)
- [Exact benchmark specification](full_harness/shared/SPECIFICATION.md)
- [Deterministic external grader](full_harness/shared/grader.sh)

The principal preserved runs are:

- `full_harness/runs/pbnfc-html8-terra-vs-harness-20260727a`
- `light/runs/pbnfc-html8-light-20260728a`

Two earlier, simpler `bnfc` development trials are retained under
`full_harness/runs/preliminary/`; they are not used in the final comparison.

## The assignment

The agents had to build `pbnfc`, a self-contained ISO C11 command-line program
that compiles a BNF grammar and recognizes hierarchical HTML-like markup.

This was intentionally more demanding than a textbook parser exercise. The
implementation had to provide:

- a BNF lexer, parser, AST, symbol resolution, epsilon productions, exact
  terminals, declared token kinds, and complete left-recursion detection;
- an HTML-like lexer for compact tags, attributes, quoted strings, and maximal
  text runs with byte/line/column locations;
- a general chart recognizer that safely handles right recursion, ambiguity,
  epsilon, and nested expansion;
- a persistent pool of exactly eight POSIX worker threads;
- parallel chart closure and scanning with worker-local candidate buffers and
  deterministic merge/deduplication;
- stable success, rejection, and grammar-error output contracts;
- strict C11/pthread compilation, project tests, documentation, worker
  statistics, and clean lifecycle behavior.

The public grader checks 12 build and functional behaviors. Later independent
review added edge-case and quality probes for deep recursion, token
classification, text preservation, chart closure, epsilon handling, empty
strings, one-line diagnostics, ambiguity, sanitizers, coverage, and leaks.

## Experiment design

All compared implementations started from fresh seed repositories containing
the same specification and repository guidance. The final full and light runs
use a byte-identical specification with SHA-256:

```text
86d2588cb2631957e68cc2629e64d4f31e5a55e398e90d71fbef50679af8c6ae
```

The full benchmark launched the standalone Terra process and the full
manager/worker harness concurrently. The later light benchmark reused the same
specification and grader and compared its fresh result with the preserved full
baseline. Model stochasticity and the fact that the light and full runs were
not simultaneous are documented limitations.

Each runner:

1. creates a new run directory and refuses to overwrite an existing one;
2. initializes one or more fresh seed repositories;
3. copies the immutable specification, guidance, grader, and pricing inputs;
4. starts the configured Codex process or harness;
5. waits without an artificial coding timeout;
6. reruns the same external grader; and
7. records timing, turns, handoffs, provider-reported tokens, source lines, and
   API-price-equivalent cost.

The dollar figures are calculated from supplied per-million-token rates. These
runs used ChatGPT authentication, so the figures are price equivalents for
comparison, not itemized invoices.

## Directory guide

```text
benchmarks/
├── README.md                         this introduction
├── light-vs-single-terra-high.md     final comparison and recommendation
├── full_harness/
│   ├── README.md                     full runner and measurement notes
│   ├── RESULTS.md                    full versus standalone results
│   ├── run.sh / evaluate.sh          runner and offline evaluator
│   ├── shared/                       specification, guidance, and grader
│   └── runs/
│       ├── pbnfc-html8-...           authoritative preserved full run
│       └── preliminary/              early development trials
└── light/
    ├── README.md                     light runner and measurement notes
    ├── RESULTS.md                    light versus full results
    ├── run.sh / evaluate.sh          runner and offline evaluator
    ├── development-policy.txt        prototype policy used by the runner
    └── runs/pbnfc-html8-light-...    authoritative preserved light run
```

Inside a preserved run:

- `comparison.md` and `comparison.tsv` contain headline measurements;
- `repository/` contains the final generated source artifact;
- `grader.out` contains the external functional result;
- `quality/` and `quality-audit.tsv`, when present, contain post-run audits;
- `state/.../prompts`, `outputs`, `reviews`, and `addenda` show the light
  manager/worker conversation;
- full-harness `state/.../archive` and `logs` preserve task-level decisions and
  model JSONL traces; and
- `timing.env`, `role-usage.tsv`, and pricing files support independent
  recalculation.

Raw logs deliberately retain original absolute paths and timestamps as
provenance. They can mention the machine's former `/var/home/mf/.../benchmark`
location even though the public archive now lives under `benchmarks/`.
JSONL traces include prompts, commands, tool output, and source excerpts; review
them before copying the artifacts into a different public dataset.

Generated repositories were initialized as independent Git worktrees during
the experiment. Locally, their seed metadata is preserved as
`.benchmark-git-metadata` instead of `.git`, and
[`.gitignore`](.gitignore) excludes it from publication. This keeps the
snapshots inert and ensures that adding `benchmarks/` to an outer Git
repository records the generated source files rather than
embedded-repository gitlinks. Rebuildable repository-local binaries, objects,
and dependency files are excluded for the same reason.

## Requirements

For inspection, only a text editor is needed. To rebuild and grade the generated
C artifacts, use a POSIX environment with:

- Bash, Git, GNU Make, and a C11 compiler;
- POSIX pthread support;
- `jq`, `sha256sum`, and standard Unix text tools; and
- optionally Valgrind and GCC coverage tools for the post-run quality audit.

To generate a new result, install and authenticate the Codex CLI and provide a
writable Codex home. Model access and quota are also required.

## Run the light benchmark

From the repository root:

```bash
BENCHMARK_CODEX_HOME="$HOME/.codex" \
BENCHMARK_CODEX_BIN=codex \
./benchmarks/light/run.sh
```

The default is the bundled prototype development policy and a
`workspace-write` sandbox. A unique run ID or different policy can be supplied:

```bash
BENCHMARK_RUN_ID=my-light-run \
BENCHMARK_DEVELOPMENT_POLICY=/path/to/development-policy.txt \
./benchmarks/light/run.sh
```

Re-evaluate a completed or interrupted light run without invoking a model:

```bash
./benchmarks/light/evaluate.sh ./benchmarks/light/runs/my-light-run
```

## Run the full benchmark

The unified repository contains both competitors. The Full runner emits
`HARNESS_MODE=full` and enables proactive v2 decomposition; the Light runner
emits `HARNESS_MODE=light`. Run from this checkout:

```bash
BENCHMARK_CODEX_HOME="$HOME/.codex" \
BENCHMARK_CODEX_BIN=codex \
./benchmarks/full_harness/run.sh
```

The runner starts standalone Terra High and the full Terra/Luna harness in
parallel. See [full_harness/README.md](full_harness/README.md) for details.

## Interpreting the result

The public grader gives both single Terra and light 12/12, but independent
review distinguishes their completeness. Across 12 public checks, eight
reviewed specification checks, and one sanitizer robustness check:

| Artifact | Checks passed | Observed completeness |
|---|---:|---:|
| Single Terra High | 15/21 | 71.4% |
| Light Worker–Manager | 20/21 | 95.2% |

The light run cost $3.2960 versus $0.8631 for standalone Terra, but produced
more maintainable code, repaired five specification failures left by the
standalone result, and had a 57.57% lower nominal cost per final C/header line.
Physical lines are not quality-adjusted units, so completeness, behavior, and
maintainability should be considered alongside that ratio.

On this experiment, light is the recommended default when the objective is
useful, maintainable coding output per quota. Standalone Terra remains the
cheapest way to obtain a visible-grader pass, while the full harness provides
additional robustness at much higher cost.
