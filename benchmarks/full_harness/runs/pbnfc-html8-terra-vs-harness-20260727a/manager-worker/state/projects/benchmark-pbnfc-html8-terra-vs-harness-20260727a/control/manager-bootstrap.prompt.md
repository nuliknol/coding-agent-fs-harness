Read /var/home/mf/coding-agent-fs-harness/prompts/manager-agent-event-driven.md and follow it.

HARNESS_BIN=/var/home/mf/coding-agent-fs-harness/bin
ENV_FILE=/var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/harness.env
PROJECT=benchmark-pbnfc-html8-terra-vs-harness-20260727a
PROJECT_TMP_DIR=/tmp/benchmark-pbnfc-html8-terra-vs-harness-20260727a
SPECIFICATION=/var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/repository/SPECIFICATION.md
REPOSITORY=/var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/repository
DEVELOPMENT_POLICY_FILE=
WORKER_GOAL_MODE=1

This is the bootstrap turn. Read DEVELOPMENT_POLICY_FILE when present and inspect the complete specification. First write a tab-separated project plan under PROJECT_TMP_DIR with one immutable line per specification phase or acceptance gate: ITEM_ID<TAB>TITLE. Include the full execution stack, not merely the first task. Register it with manager-init-project-plan. Then inspect the repository, write one bounded initial assignment under PROJECT_TMP_DIR with stable Root-Criterion lines for every independently verifiable acceptance criterion, and publish it with manager-publish-task including the corresponding PROJECT_PLAN_ITEM_ID. Terminate after exactly one task is published. Every harness command must receive ENV_FILE as its first argument. Do not wait for the worker and do not run any polling command.

Worker leaf-goal mode is enabled. The initial assignment must select its first Root-Criterion as Target-Criterion and contain exactly one nonempty line for each of: Execution-Mode: LEAF_GOAL, Goal-ID, Target-Criterion, Goal-Success-Evidence, Focused-Validation, Allowed-Scope, Baseline-Boundary, and Hard-Block-Conditions. Give the goal a stable identifier. Success evidence and validation must be independently checkable; allowed scope and genuine hard-block conditions must be explicit. The worker may span multiple internal turns, but the manager will receive only its terminal result.

Context: authorized local development in my own repository. Task type: benign software engineering. Do not perform offensive security, credential extraction, vulnerability exploitation, malware behavior, unauthorized access, network scanning, or bypassing security controls. Use only the listed local project files needed for the requested implementation: SPECIFICATION and files explicitly necessary to create one bounded initial assignment.
