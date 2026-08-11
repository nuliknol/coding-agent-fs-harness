# Strict full build, regression suite, concurrency checks, README, and final validation

Task-ID: 010-final-validation
Project-Plan-Item: 010
Root-Criterion: p010.readme-contract
Root-Criterion: p010.regression-and-concurrency-targets
Root-Criterion: p010.final-external-validation
Execution-Mode: LEAF_GOAL
Goal-ID: p010.goal.readme-contract
Target-Criterion: p010.readme-contract
Goal-Success-Evidence: README documents grammar syntax, markup tokenization, parallel merge invariants, limitations, runnable examples, output format, and exit statuses without changing public behavior.
Focused-Validation: Run test -s README.md.
Allowed-Scope: README.md only.
Baseline-Boundary: items 001–009 are accepted; aggregate regression/concurrency targets and required final external validation remain separate later leaves.
Hard-Block-Conditions: None expected; repository-local documentation work must be resolved within scope.

Implement only the documentation criterion. Do not change source, Makefile targets, generated artifacts, or execute aggregate/external checks in this leaf.
