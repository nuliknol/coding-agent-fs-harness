DECISION: REVISE

1. `ADD-005` — The chart closure misses already-completed epsilon constituents.

   - `Specification:` “Right recursion, epsilon, nested expansion, and ambiguous alternatives must terminate safely,” and the engine must recognize the compiled grammar’s full language.
   - `Evidence:` `closure_task()` in `src/recognizer.c` predicts a nonterminal but does not advance that newly added caller against an already-completed same-position item. The valid, acyclic epsilon grammar `S ::= X B A; X ::= A C; A ::=; B ::=; C ::=;` rejects an empty input: exit `1`, `REJECT offset=0 line=1 column=1 expected=markup token`; it must accept.
   - `Required correction:` Restore complete Earley closure semantics while retaining deterministic worker merges: when an item expecting a nonterminal is added and that nonterminal is already complete at the chart position, emit the advanced item (or implement an equivalent correct agenda invariant).
   - `Verification:` Run the grammar above against an empty input; it exits `0` with `ACCEPT tokens=0`.

`make clean all`, `make test`, and `../grader.sh "$PWD"` pass (12/12), but they do not cover this required epsilon/nested-expansion case.