# Task Assignment

Project: PROJECT_NAME
Task-ID: TASK_ID
Revision: 0
Repository: /absolute/path/to/repository
Status: READY

## Objective

Describe one bounded implementation objective.

## Required behavior

1. Describe externally observable behavior.
2. Describe validation and error behavior.
3. Describe compatibility requirements.

## Acceptance criteria

- Existing tests continue to pass.
- New behavior has deterministic tests.
- No unrelated subsystem is modified.
- The worker does not create, stage, or commit Git changes.

## Relevant files

- path/to/source.c
- path/to/header.h
- path/to/test.c

## Constraints

- Use the existing project architecture.
- Do not redesign unrelated components.
- Do not make Git commits.
- Stop and report a blocker instead of inventing an incompatible interface.

## Validation commands

```text
make
make test
```

## Completion protocol

1. Implement the task.
2. Run the validation commands.
3. Prepare a result report using `result-template.md`.
4. Call `worker-complete-task ENV_FILE TASK_ID SESSION_ID RESULT_FILE`.
5. Do not claim completion merely because the code compiles.
