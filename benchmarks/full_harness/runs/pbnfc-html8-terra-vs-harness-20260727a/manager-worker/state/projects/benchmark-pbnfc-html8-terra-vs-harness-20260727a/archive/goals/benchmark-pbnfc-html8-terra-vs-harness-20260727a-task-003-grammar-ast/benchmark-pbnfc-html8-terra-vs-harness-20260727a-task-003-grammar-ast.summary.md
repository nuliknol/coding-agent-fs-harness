# Worker Leaf Goal

Task-ID: 003-grammar-ast
Goal-ID: p003.goal.grammar-ast-parse-storage
Target-Criterion: p003.grammar-ast-parse-storage
Goal-Success-Evidence: A caller-owned grammar AST API parses the lexer token stream into owned declarations, productions, alternatives (including epsilon), terminal/reference/nonterminal symbols, and frees all owned storage safely; a focused AST smoke parses a representative grammar and checks its retained structure.
Focused-Validation: Run `make test-grammar-ast-core`; it must build the parser/AST layer and pass one representative grammar structure smoke with exit status 0.
Allowed-Scope: Modify only `Makefile`, `src/`, `include/`, and a focused `tests/` AST smoke; preserve lexer APIs and prior test target, and do not implement CLI file loading, markup lexing, chart recognition, worker pooling, symbol resolution, or left-recursion checking.
Baseline-Boundary: Plan items 001 and 002 are accepted; the repository has a complete tokenizing grammar lexer but no grammar AST, parser, owned grammar storage, or AST smoke target.
Hard-Block-Conditions: None expected: no authorization, secret, external service, or unresolved product decision is needed; report a local compiler/toolchain failure with exact command output rather than changing task scope.

Iteration receipts are authoritative in: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/control/goals/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-003-grammar-ast.iterations.tsv

## Terminal worker outcome

Outcome: COMPLETE
Result: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/state/projects/benchmark-pbnfc-html8-terra-vs-harness-20260727a/results/benchmark-pbnfc-html8-terra-vs-harness-20260727a-task-003-grammar-ast.result.md
Published-At: 2026-07-28T04:18:01Z
