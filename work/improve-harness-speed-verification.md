# Harness Throughput Improvement Verification

Date: 2026-08-18
Version: 5.18.36

## Retained baseline

The production-state baseline captured before implementation was:

- 2,096 total agent invocations;
- 657 automatic replans;
- 321 rejected reviews;
- 173 denied context expansions;
- 206 unconditional fresh CMake configurations;
- 22 completed DAG nodes out of 461;
- four configured worker slots per active ACP project, with zero safe-ready nodes
  at the sample boundary;
- one completed story result dormant after an uncommitted manager review.

## Deterministic parallelism fixture

`tests/test_speed_improvements.py` retains a four-node, two-chain DAG. Before
this implementation the harness did not report critical path, theoretical
width, conflict-reduced width, or current safe-ready width. The installed
analyzer reports:

```text
critical_path_length=2
maximum_dag_width=2
conflict_reduced_max_width=2
dependency_ready_width=2
safe_ready_width=1
```

The distinction is intentional: the initial two ready nodes have an explicit
semantic conflict, while a later frontier exposes two independent nodes.

## Qualified regression evidence

- Python Context Broker and speed tests: 24 passed.
- Full v4.4 harness suite: passed.
- ACP protocol suite: passed.
- ACP parallel integration suite: passed.
- Supervisor result barrier suite: passed.
- Decomposition v2 suite: passed.
- Architecture guard suite: passed.
- Repository index suite: passed.
- Module boundary suite: passed.
- Manager context rotation suite: passed.
- Independent manager batch transaction suite: passed.
- Luna-only convergence suite: passed.
- Root liveness and dependency invalidation suite: passed.

## Retained production throughput measurements

The corrected historical utilization calculation pairs legacy and current
worker lifecycle events without double-counting them and ignores unverifiable
open intervals. Before recovery, representative retained projects reported:

| Project | Worker / manager invocations | Implementation yield | Control amplification | Critical path | Max / conflict width | Slot utilization |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| compmod-wc-3 | 123 / 273 | 7.32% | 45.56 per node | 26 | 4 / 4 | 0.80% |
| compmod-wc-4 | 74 / 193 | 4.05% | 90.33 per node | 23 | 6 / 2 | 0.90% |
| dplm-final-v2 | 100 / 301 | 4.00% | 119.00 per node | 18 | 31 / 2 | 0.56% |
| dpvis-w2-a2 | 155 / 241 | 0.65% | 352.00 per node | 19 | 3 / 2 | 1.26% |

These values establish the retained pre-improvement comparison boundary. They
also show that low occupancy was caused by control-plane amplification and a
zero safe-ready frontier, not by a missing four-worker process limit.

## Production rollout and recovery

- The implementation was deployed at commit `2fe2a08`, version 5.18.36. After
  committing the audited rollout records, development and production both
  matched the same final HEAD; the production tree was clean.
- Closure-cut revisions `CMCLM-003-revision-80` and `N04-revision-163` passed
  deterministic cut validation, published, and launched Luna workers.
- The retained `DAG-014` worker transaction resumed after deterministic build
  evidence recovery.
- The story source-audit root was explicitly rearmed under the installed fix.
  Revision 17 preserved `FOCUSED: IT-A19-SOURCE-001 source-only requirement
  audit.` and launched a Luna worker; it did not repeat the nonexistent
  `source-audit-evidence-check` command.
- A final eight-project fleet snapshot showed two completed projects and six
  running projects, with no paused or recovery-stalled harness.
