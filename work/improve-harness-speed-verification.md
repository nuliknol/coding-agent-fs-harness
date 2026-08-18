# Harness Throughput Improvement Verification

Date: 2026-08-18
Version: 5.18.33

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

Production fleet measurements and resumed-root evidence are recorded after the
deployment section of the implementation plan is completed.
