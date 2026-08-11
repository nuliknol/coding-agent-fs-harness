# Checkpointed Task Increment

Project: benchmark-bnfc-terra-vs-harness-20260727b

Task-ID: bnfc-01-foundation-revision-01

Task-Root: bnfc-01-foundation

Environment-File: /var/home/mf/coding-agent-fs-harness/benchmark/runs/bnfc-terra-vs-harness-20260727b/manager-worker/harness.env

Checkpointed-At: 2026-07-28T03:39:20Z

Artifact-Directory: /var/home/mf/coding-agent-fs-harness/benchmark/runs/bnfc-terra-vs-harness-20260727b/manager-worker/state/projects/benchmark-bnfc-terra-vs-harness-20260727b/archive/checkpoints/benchmark-bnfc-terra-vs-harness-20260727b-task-bnfc-01-foundation-revision-01

## Review notes

# Manager Review Record

Task-ID: bnfc-01-foundation-revision-01
Decision: CHECKPOINT
Progress-Percent: 66%
Improvement-Percent: 33%
Verified-Criterion: foundation.cli.required-options
Checkpoint-Path: include/cli.h
Checkpoint-Path: src/cli.c
Checkpoint-Path: src/main.c

## Specification comparison

The increment completes the second foundation criterion: the required `--grammar PATH` and `--input STRING` options are mandatory and unique, `--start NAME` is optional and unique, and malformed command lines emit `GRAMMAR_ERROR` with status 2. Grammar loading and lexing remain for the final ordered foundation leaf.

## Increment verification

- [PASS] foundation.cli.required-options — direct inspection of `src/cli.c` shows all option values are copied, duplicate/missing/unknown/positional cases are rejected, and `src/main.c` emits `GRAMMAR_ERROR` then exits 2.

## Validation executed

- [PASS] `make clean all` — exited 0 with `-std=c11 -Wall -Wextra -Werror -pedantic` on both sources.
- [PASS] focused CLI smoke — no arguments, a missing value for each of `--grammar`, `--input`, and `--start`, missing required input, duplicate `--grammar`, duplicate `--start`, an unknown option, and a positional argument each printed `GRAMMAR_ERROR` and exited 2; complete tuples, including empty input and `--start`, exited 0 without a command-line error.

## Scope and regression review

Reviewed `include/cli.h`, `src/cli.c`, and `src/main.c`. The CLI API owns and releases copied arguments, preserves the prior strict build, and introduces no grammar lexer, parser, semantic validation, recognizer, or final acceptance/rejection behavior. `git diff --check` exited 0.

## Remaining root criteria

- `foundation.lexer.grammar-tokens`

## Conclusion

The second leaf criterion is correct and independently verified, while the root remains incomplete. Checkpoint.

