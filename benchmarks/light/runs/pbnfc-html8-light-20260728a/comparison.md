# Full harness versus light harness

The light run used the byte-identical archived `pbnfc` specification and the
same deterministic external grader as the full-harness baseline.

| Metric | Full harness | Light harness | Light/full |
|---|---:|---:|---:|
| Functional score | 12/12 | 12/12 | — |
| Wall seconds | 8055 | 2716 | 0.3372x |
| Completed model turns | 81 | 13 | 0.1605x |
| Manager/worker handoffs | 81 | 12 | 0.1481x |
| Input tokens including cache | 41023421 | 9337500 | 0.2276x |
| Cached-input reads | 39280640 | 8833280 | 0.2249x |
| Uncached input | 1742781 | 504220 | 0.2893x |
| Output tokens | 363966 | 120848 | 0.3320x |
| API-price-equivalent USD | 13.467938 | 3.296026 | 0.2447x |
| C/header physical lines | 3851 | 1710 | 0.4440x |

At the supplied rates, the light run used **75.53% less
API-price-equivalent cost** than the full harness.

## Light role breakdown

| Role | Turns | Input / cached / uncached | Output | Cost equivalent |
|---|---:|---:|---:|---:|
| Terra manager | 7 | 2131741 / 1840896 / 290845 | 52332 | $1.972317 |
| Luna worker | 6 | 7205759 / 6992384 / 213375 | 68516 | $1.323709 |
| Combined | 13 | 9337500 / 8833280 / 504220 | 120848 | **$3.296026** |

The light harness completed 6 Luna implementation/remediation cycle(s).
Provider usage is deduplicated by Codex thread ID: resumed cumulative Luna
snapshots are not added repeatedly.

## Artifact-size indicators

| Measure | Full harness | Light harness |
|---|---:|---:|
| C/header files | 15 | 11 |
| C/header physical lines | 3851 | 1710 |
| Project test files | 12 | 10 |
| Project test physical lines | 1999 | 100 |
| README physical lines | 159 | 83 |

Functional grader output is in [grader.out](grader.out), exact per-role usage in
[role-usage.tsv](role-usage.tsv), and machine-readable comparison data in
[comparison.tsv](comparison.tsv).

The dollar values are API-price equivalents based on the supplied token rates.
Because this run uses ChatGPT authentication, they are not an itemized invoice.
This is one fresh light run compared with one earlier full run, so model
stochasticity and run-time conditions remain experimental limitations.
