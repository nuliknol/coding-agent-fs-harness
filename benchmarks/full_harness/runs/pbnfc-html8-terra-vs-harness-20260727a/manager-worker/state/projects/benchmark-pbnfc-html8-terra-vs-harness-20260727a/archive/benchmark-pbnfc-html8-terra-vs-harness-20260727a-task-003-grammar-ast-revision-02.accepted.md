# Accepted Task

Project: benchmark-pbnfc-html8-terra-vs-harness-20260727a

Task-ID: 003-grammar-ast-revision-02

Environment-File: /var/home/mf/coding-agent-fs-harness/benchmark/runs/pbnfc-html8-terra-vs-harness-20260727a/manager-worker/harness.env

Accepted-At: 2026-07-28T04:31:37Z

## Review notes

# Manager Review Record

Task-ID: 003-grammar-ast-revision-02
Decision: ACCEPT
Progress-Percent: 100%
Verified-Criterion: p003.left-recursion-validation

## Specification comparison

The completed grammar layer owns parsed AST data, validates declarations and symbols, and rejects direct/indirect left recursion using nullable-leading analysis before recognition.

## Acceptance-criteria verification

- [PASS] p003.grammar-ast-parse-storage — prior checkpoint proves owned declarations, productions, typed symbols, decoded terminals, epsilon alternatives, and safe freeing.
- [PASS] p003.symbol-resolution-validation — prior checkpoint proves directive/order, duplicate, and undefined-symbol diagnostics.
- [PASS] p003.left-recursion-validation — focused cases reject direct, indirect, and nullable-mediated left recursion while accepting right recursion and epsilon-safe grammars.

## Feature verification

- [PASS] source-located recursion diagnostic — validation emits one deterministic `GRAMMAR_ERROR left recursion detected` at the cycle-closing symbol.

## Validation executed

- [PASS] `make test-grammar-ast-core` — exited 0 with strict compilation and the representative plus validation-case smoke.

## Scope and regression review

Reviewed AST source/test changes only; they preserve ownership and prior validation behavior and add no CLI, markup, recognizer, or worker-pool work.

## Conclusion

All required behavior was independently verified. Accept.

