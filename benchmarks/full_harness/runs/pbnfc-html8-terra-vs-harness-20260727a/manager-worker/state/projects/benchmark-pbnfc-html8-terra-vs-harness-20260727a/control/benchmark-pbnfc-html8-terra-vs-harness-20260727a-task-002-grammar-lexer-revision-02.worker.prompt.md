Read /var/home/mf/coding-agent-fs-harness/prompts/worker-agent-event-driven.md and follow it.

HARNESS_BIN=/var/home/mf/coding-agent-fs-harness/bin
ENV_FILE=/var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/harness.env
PROJECT=benchmark-pbnfc-html8-terra-vs-harness-20260727a
PROJECT_TMP_DIR=/tmp/benchmark-pbnfc-html8-terra-vs-harness-20260727a
REPOSITORY=/var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/repository
TASK_ID=002-grammar-lexer-revision-02
TASK_FILE=/var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/running/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-002-grammar-lexer-revision-02.running.md
TASK_ROOT=002-grammar-lexer
ROOT_ASSIGNMENT_FILE=/var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/control/progress/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-002-grammar-lexer.root-assignment.md
PROGRESS_FILE=/var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/control/progress/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-002-grammar-lexer.progress.md
STARTING_PROGRESS_PERCENT=66
DEVELOPMENT_POLICY_FILE=
SESSION=worker-20260728T040932Z-13c9d64b
WORKER_CONTEXT_MODE=fresh
WORKER_CONTEXT_REASON=fresh
WORKER_RETAINED_REJECTIONS=0
CLOSURE_MODE=0
CLOSURE_MAX_FIXES=2
CLOSURE_MAX_SMOKE_RUNS=3
WORKER_GOAL_MODE=1
EXECUTION_MODE=WORKER
GOAL_ID=p002.goal.grammar-lexer-errors
GOAL_TARGET_CRITERION=p002.grammar-lexer-errors
GOAL_STATE_FILE=/var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/control/goals/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-002-grammar-lexer-revision-02.goal
GOAL_SUMMARY_FILE=/var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/control/goals/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-002-grammar-lexer-revision-02.summary.md
GOAL_ITERATION_LEDGER_FILE=/var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/control/goals/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-002-grammar-lexer-revision-02.iterations.tsv
GOAL_PROCESS_MAX_FIXES=3
GOAL_PROCESS_MAX_SMOKE_RUNS=4

The task is already claimed by this launcher. Read DEVELOPMENT_POLICY_FILE when present, then ROOT_ASSIGNMENT_FILE, PROGRESS_FILE, and TASK_FILE completely. The current files are authoritative even when this turn resumes an earlier worker conversation. Preserve verified work and continue from STARTING_PROGRESS_PERCENT rather than reimplementing the root task from zero. Implement exactly the remaining bounded assignment, validate only the developed feature according to the prototype policy, write any scratch files and the result report under PROJECT_TMP_DIR, publish the result with worker-complete-task, and terminate. Do not wait for another task. Do not create, stage, or commit Git changes.

Leaf-goal execution is active. This is one logical goal for the independently verifiable criterion GOAL_TARGET_CRITERION, even if it requires several Codex turns. Read GOAL_SUMMARY_FILE and GOAL_ITERATION_LEDGER_FILE when they contain prior iterations. Continue diagnosing, implementing, and running focused validation until exactly one of these terminal outcomes is true:

- COMPLETE: the goal success evidence and focused validation in TASK_FILE pass.
- NEEDS_DECOMPOSITION: the criterion is still too broad or repeated strategy attempts cannot make material movement.
- HARD_BLOCKED: an explicit Hard-Block-Conditions boundary in TASK_FILE is actually met.

Current durable iteration: 0
Current boundary: p002 core and terminal/reference criteria are checkpointed at 66%; invalid inputs already return false in some paths, but no focused independently checked contract yet proves one deterministic located diagnostic for every required malformed lexical category.
Current workspace fingerprint: sha256:660456964af4a45ea224ab9304a1c1076429e07fd8e32a29201e60c98e6d9496

When another bounded turn is useful, write a receipt under PROJECT_TMP_DIR with exactly one Task-ID, Goal-ID, Iteration, Outcome: CONTINUE, Boundary-Before, Boundary-After, Workspace-Fingerprint-Before, and Workspace-Fingerprint-After line, plus nonempty sections named "## Progress made", "## Validation performed", "## Next bounded action", and "## Scope check". Iteration must be 1; the before values must equal the current durable values above. Obtain the exact after value with:

/var/home/mf/coding-agent-fs-harness/bin/harness-workspace-fingerprint "/var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/harness.env"

Publish the receipt with:

/var/home/mf/coding-agent-fs-harness/bin/worker-continue-task "/var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/harness.env" "002-grammar-lexer-revision-02" "worker-20260728T040932Z-13c9d64b" RECEIPT_FILE

After that command succeeds, end this Codex turn. The harness will resume the same logical goal automatically. A CONTINUE receipt must record a changed boundary, changed workspace, or genuinely new evidence/strategy. Process-local work should stay within 3 small corrections and 4 focused smoke executions before publishing CONTINUE.

For a terminal result, include "Goal-ID: p002.goal.grammar-lexer-errors" and exactly one "Goal-Outcome: COMPLETE|NEEDS_DECOMPOSITION|HARD_BLOCKED", retain the normal worker result headings, publish it with worker-complete-task, and terminate. Do not use NEEDS_DECOMPOSITION merely because another ordinary diagnostic/fix turn is required. Do not use HARD_BLOCKED for test failure, complexity, token pressure, or lack of immediate progress.

Context: authorized local development in my own repository. Task type: benign software engineering. Do not perform offensive security, credential extraction, vulnerability exploitation, malware behavior, unauthorized access, network scanning, or bypassing security controls. Use only the listed local project files needed for the requested implementation: TASK_FILE and the files explicitly referenced by that bounded assignment.
