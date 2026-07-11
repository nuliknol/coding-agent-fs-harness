# Task Assignment

Project: PROJECT_NAME
Task-ID: TASK_ID
Revision: 0
Task-Root: TASK_ID
Starting-Progress: 0%
Repository: /absolute/path/to/repository
Status: READY

## Objective

Describe one bounded implementation objective.

## Required behavior

1. Describe externally observable behavior.
2. Describe validation and error behavior.
3. Describe compatibility requirements.

## Acceptance criteria

- The affected build/compile target succeeds.
- One focused happy-path manual or smoke test visibly demonstrates the feature.
- One focused regression test is required only when this task fixes a bug.
- No unrelated subsystem is modified.
- The worker does not create, stage, or commit Git changes.

## Relevant files

- path/to/source.c
- path/to/header.h
- path/to/test.c

## Constraints

- Follow the repository's prototype / feature-first development policy.
- Preserve verified work recorded in the root progress checkpoint.
- Do not run broad unit-test suites, aggregate tests, or full CTest unless the
  human-owned specification explicitly requires them.
- Record unrelated failures as known limitations; do not repair them.
- Use the existing project architecture.
- Do not redesign unrelated components.
- Do not make Git commits.
- Stop and report a blocker instead of inventing an incompatible interface.

## Validation commands

```text
make affected-target
./affected-smoke --happy-path
```

## Completion protocol

1. Implement the task.
2. Run the validation commands.
3. Prepare a result report using `result-template.md`.
4. Call `worker-complete-task ENV_FILE TASK_ID SESSION_ID RESULT_FILE`.
5. Do not claim completion merely because the code compiles.
