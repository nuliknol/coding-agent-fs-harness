# Leaf-Goal Task Assignment

Project: PROJECT_NAME
Task-ID: TASK_ID
Task-Root: ROOT_TASK_ID
Starting-Progress: N%
Status: READY

Execution-Mode: LEAF_GOAL
Goal-ID: stable.goal.identifier
Target-Criterion: first.unmet.leaf
Goal-Success-Evidence: State the exact independently verifiable passing evidence.
Focused-Validation: State the affected build and one focused validation command.
Allowed-Scope: State the exact file and behavior boundary.
Baseline-Boundary: State the durable starting failure, diagnostic, or evidence boundary.
Hard-Block-Conditions: List only explicit authority, external dependency, or incompatible observable product/specification outcomes. Worker file ownership, exclusive/forbidden paths, and baseline restrictions route to manager baseline remediation.
Mandatory-Git-Refs: NONE
<!-- For a Git branch deliverable, add Publish-Branch and Publish-Base metadata. -->
Leaf-Type: LOCAL_IMPLEMENTATION
Complexity-Class: LOW
Worker-Route: LUNA
Depends-On: dependency.node.id
Deliverable: State the one independently useful artifact or behavior.
Required-Symbols: exact_symbol,other_symbol
Context-Paths: path/to/file.c,path/to/focused_test.c
Architecture-Decisions: NONE
Validation-Class: FOCUSED
Affected-Invariants: INV-example
Consumed-Decisions: ADR-example
Produced-Decisions: -
Edge-Contracts: EDGE-example
Health-Gates: -
Expected-Max-Implementation-Files: 3
Expected-Max-Worker-Turns: 2

<!-- New roots must also declare all immutable Root-Criterion lines. A new
root's Target-Criterion is its first Root-Criterion. Continuations omit the
Root-Criterion inventory because they inherit it from the root assignment. -->
Root-Criterion: first.unmet.leaf
Root-Criterion: later.leaf

## Objective

Complete the target leaf criterion without broadening the root.

## Acceptance criteria

- Goal-Success-Evidence is independently observable.
- Focused-Validation passes.
- Previously verified behavior remains intact.

## Relevant files

- path/to/affected-file

## Constraints

- Preserve durable checkpoints and the live workspace.
- Treat the context capsule as the bounded discovery surface.
- Publish a CONTINUE receipt when another bounded process turn is useful.
- Use NEEDS_DECOMPOSITION only when a materially smaller criterion or changed
  manager strategy is required.
- Use HARD_BLOCKED only when an explicit Hard-Block-Conditions boundary is met;
  the manager will separately decide whether recovery is repository-local or
  genuinely human-dependent.

## Validation commands

```text
make affected-target
./affected-smoke --focused-case
```
