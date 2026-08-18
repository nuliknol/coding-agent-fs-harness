
Your harness is currently suffering from **control-plane amplification**. The coding models are not the bottleneck. The harness is spending most of its inference budget proving, rejecting, repairing, re-planning, and rediscovering whether agents are allowed to do work.

The striking numbers are not `capacity=4`; they are:

* 2,096 agent invocations for only 22 completed plan items.
* 321 rejections and 657 replans.
* 173 rejected context expansions.
* 206 fresh CMake configurations.
* Only 22 of 461 plan items complete.

So at the moment:

[
\boxed{\text{more parallelism}\neq\text{more progress}}
]

unless you first increase the probability that a dispatched worker actually produces useful accepted work.

## The most important thing: don't parallelize the rejection loop

With roughly 72% of reviewed revisions rejected, immediately running four workers could turn:

```text
waste
waste
waste
useful work
```

into:

```text
4 × waste
4 × quota burn
4 × simultaneous remediation
```

much faster.

I would optimize in this order:

[
\boxed{
\text{liveness}
\rightarrow
\text{fast-path yield}
\rightarrow
\text{context resolution}
\rightarrow
\text{parallelism}
}
]

Once perhaps 80–90% of well-admitted routine leaves normally reach useful checkpoint/acceptance without structural replan, then `N=4` becomes enormously valuable.

---

# 1. The harness currently has a slow path, but almost everything falls into it

The architecture you want should have two paths.

### Fast path

```text
TASK
 ↓
Worker
 ↓
Context Broker if needed
 ↓
patch
 ↓
focused validation
 ↓
review
 ↓
ACCEPT
```

Maybe 1–3 inference calls total.

### Exceptional path

```text
TASK
 ↓
worker discovers real boundary defect
 ↓
ACP
 ↓
manager
 ↓
scope/prerequisite/DAG change
 ↓
resume
```

Right now the exceptional path appears to have become the normal path:

```text
TASK
 ↓
missing context
 ↓
deny
 ↓
NEEDS_DECOMPOSITION
 ↓
review
 ↓
replan
 ↓
worker
 ↓
missing context
 ...
```

That is the central problem.

---

# 2. Context Closure is currently defeating ACP

This may be the single highest-return fix.

You added ACP specifically so the worker can discover:

> I need X.

But then Context Closure says:

> No.

Then Luna has to terminate, manager has to reason, task gets replanned, and eventually somebody discovers that Luna really did need X.

That turns an interaction that should cost approximately:

```text
NEED_CONTEXT(X)
→ HERE_IS_X
```

into several model invocations.

I would change the philosophy substantially:

## Reads should be cheap; writes should be guarded

The security/authority distinction should be:

[
\boxed{\text{read expansion is permissive}}
]

[
\boxed{\text{mutation expansion is conservative}}
]

If the worker asks:

```text
NEED_TYPE foo_descriptor
NEED_CALLER foo_submit
NEED_PRODUCER descriptor_writer
NEED_CONTEXT src/foo.c
```

and the Context Broker can prove that it is a direct semantic neighbor of the assignment, **give it to the worker**.

No manager.

No replan.

No terminal worker result.

Especially if the requested file/symbol is already mentioned by:

* the assignment,
* required symbols,
* validation diagnostic,
* direct caller/callee,
* producer/consumer graph,
* owning type,
* build target,
* architecture edge.

Those should be almost automatic.

---

# 3. Context requests should generally keep the worker session alive logically

Not the process—the process can exit, as you designed.

Conceptually:

```text
worker session H
    ↓
NEED_CONTEXT(X)
    ↓
process exits

Context Broker resolves X

codex exec --resume H
    ↓
worker receives only X
```

No manager boundary crossed.

That is exactly what ACP should buy you.

Your manager should not even know about most of these operations except through telemetry.

---

# 4. `NEEDS_DECOMPOSITION` is currently too expensive

Your coding agent's recommendation here is exactly right.

A deterministic condition such as:

```text
context missing
scope structurally incomplete
complexity threshold exceeded
```

doesn't automatically require an LLM review.

If the machine can establish:

[
\operatorname{ContextIncomplete}(T,X)
]

then the transition can be:

```text
T
 ↓
deterministic graph/context analyzer
 ↓
T1, T2
```

or:

```text
T
 ↓
add context X
 ↓
resume
```

The manager should wake only when there is a **semantic choice**.

That's the token-mining hierarchy again:

```text
deterministic rule
      ↓ if insufficient
Context Broker
      ↓ if insufficient
manager reasoning
      ↓ if insufficient
human authority
```

Do not jump straight from worker to manager.

---

# 5. The silent manager stall is more serious than a performance bug

This:

```text
SUPERVISOR_REVIEW_LEFT_UNCOMMITTED
retry=suppressed_until_state_change
```

followed by no state change is a **liveness violation**.

You need an invariant:

[
\boxed{
\text{Every terminal worker result eventually reaches a terminal control-plane transition.}
}
]

Formally:

[
WorkerTerminal(r)
\Rightarrow
\Diamond
(
ACCEPT
\lor
CHECKPOINT
\lor
REJECT
\lor
ERROR
\lor
PAUSED
)
]

where (\Diamond) means "eventually."

There should be no legal state:

```text
terminal result exists
+
no committed manager decision
+
no process running
+
status says running
```

That should be impossible by construction.

I would fix this before adding additional parallelism because otherwise you'll create four times as many possible silent zombies.

---

# 6. Then we get to the really interesting parallelism problem

Your scheduler has four slots.

But the decomposition produces:

[
ParallelReady(G)=\varnothing.
]

That's not a scheduler problem.

That's a **graph-construction problem**.

And I think the report reveals something particularly important:

> You are probably using files/directories as a proxy for semantic conflict.

That's too coarse.

---

# 7. Same file does not mean same task

Suppose:

```c
foo_parse()
foo_encode()
foo_validate()
foo_write()
```

all live in:

```text
src/foo.c
```

Four DAG nodes touching `src/foo.c` currently look conflicting.

But perhaps:

[
W_1\rightarrow foo_parse
]

[
W_2\rightarrow foo_encode
]

and they have no semantic dependency.

Then:

[
\operatorname{SameFile}(W_1,W_2)
]

does **not** imply:

[
\operatorname{Conflict}(W_1,W_2).
]

This may be costing you enormous parallelism.

---

# 8. Move mutation capabilities from file granularity toward symbol granularity

Conceptually:

```text
write:
    src/foo.c
```

becomes:

```text
write-symbol:
    src/foo.c::foo_parse
```

or:

```text
write-region:
    AST(function=foo_parse)
```

Then your scheduler can understand:

```text
worker A:
    foo_parse()

worker B:
    foo_encode()

worker C:
    foo_validate()

worker D:
    test_foo_parse()
```

and run them concurrently.

This is where SCIP/Joern/clang AST-style infrastructure becomes extraordinarily useful.

---

# 9. Separate textual conflict from semantic conflict

I would define three levels:

### Level 0 — no conflict

Different files/symbols, no architecture coupling.

Run freely.

### Level 1 — textual overlap, semantic independence

Same file, different functions/regions.

Run in isolated worktrees and merge later.

### Level 2 — semantic conflict

Same representation, ownership rule, public contract, concurrency protocol, or overlapping symbol.

Serialize.

So:

[
Conflict(A,B)=
TextualConflict(A,B)
\lor
SemanticConflict(A,B)
]

is too conservative.

Instead:

[
Serialize(A,B)
]

should primarily follow:

[
SemanticConflict(A,B).
]

Textual conflict can often be handled by source-control machinery.

---

# 10. Build an explicit conflict graph

You already have the dependency DAG:

[
G_D=(V,E_D).
]

Add a second graph:

[
G_C=(V,E_C)
]

where:

[
(A,B)\in E_C
]

means:

> A and B may be dependency-ready simultaneously, but must not execute concurrently.

Then scheduler operation becomes:

1. Find dependency-ready nodes.
2. Construct conflict relations.
3. Choose up to (N) mutually non-conflicting nodes.

So for (N=4):

[
B=
{v_1,v_2,v_3,v_4}
]

such that:

[
\forall i\neq j:
(v_i,v_j)\notin E_C.
]

This is essentially an independent-set scheduling problem.

You don't need the optimal maximum independent set.

A greedy scheduler is fine initially.

---

# 11. Parallelism should operate over isolated worktrees

Your previous design document was right about this.

Each worker should have:

```text
common immutable base
+
private worktree
+
private build directory
```

Then:

```text
W1 ── patch P1
W2 ── patch P2
W3 ── patch P3
W4 ── patch P4
```

Manager/integration service combines accepted patches.

This changes the meaning of parallel conflict.

Two workers modifying different functions in one C file are no longer an immediate problem.

Git or an AST-aware merger can often combine them mechanically.

If it cannot:

```text
MERGE_CONFLICT
```

becomes an integration event.

---

# 12. Headers and shared representations should become producer nodes

Suppose four tasks all need a new struct field.

Bad decomposition:

```text
W1 modifies struct
W2 modifies struct
W3 modifies struct
W4 modifies struct
```

Good decomposition:

```text
           contract/header node
                  │
         ┌────────┼─────────┐
         ▼        ▼         ▼
        W1       W2        W3
```

The shared contract is accepted first.

Then all consumers execute concurrently.

This will expose much more parallelism.

---

# 13. Your DAG constructor should optimize for critical path, not number of nodes

This is important.

Currently decomposition seems focused heavily on:

[
\operatorname{LunaReady}(T).
]

Add another objective:

[
\boxed{\text{minimize critical-path length}}
]

subject to correctness.

You want something like:

[
\min L(G)
]

where (L(G)) is the longest dependency path.

For example:

### Bad

```text
A → B → C → D → E → F
```

Critical path:

[
6.
]

### Better

```text
       ┌→ B → D ┐
A ─────┤        ├→ F
       └→ C → E ┘
```

Critical path:

[
4.
]

Same amount of work.

Much higher available parallelism.

---

# 14. Add a decomposition metric: exposed parallelism

Your reports should now include:

[
P_{\text{ready}}
================

|\text{dependency-ready nodes}|.
]

Also:

[
P_{\text{safe}}
===============

|\text{mutually non-conflicting ready nodes}|.
]

And:

[
U_{\text{worker}}
=================

\frac{\text{worker-slot active time}}
{N\times\text{wall time}}.
]

Right now you apparently have:

[
N=4
]

but:

[
U_{\text{worker}}\approx \text{very low}.
]

That needs to become a first-class decomposition quality metric.

---

# 15. You can measure the theoretical maximum before running anything

Once a DAG is generated, compute:

```text
node count
critical-path length
maximum width
average ready width
conflict-reduced width
```

If you request:

```text
worker capacity = 4
```

but the generated plan has:

[
P_{\text{safe,max}}=1,
]

the planner should get a diagnostic **before project execution begins**:

> Plan structurally cannot use configured worker capacity.

That could cause a decomposition retry asking explicitly:

> preserve semantics while exposing independent branches where possible.

---

# 16. Do not force fake parallelism

There is a trap here.

If the task really is:

```text
representation
    ↓
parser
    ↓
lowering
    ↓
executor
```

then that's the dependency structure.

Don't invent parallelism.

But many large projects naturally contain huge width:

```text
                 base API
                    │
       ┌────────────┼─────────────┐
       ▼            ▼             ▼
     parser       storage       network
       │            │             │
       ▼            ▼             ▼
     tests        tests         tests
       └────────────┼─────────────┘
                    ▼
                integration
```

A good architecture should expose it.

---

# 17. CMake configuration is another obvious target

206 fresh configurations for 22 completed nodes is a flashing red light.

Configuration should generally be amortized.

You want:

```text
repository baseline
     ↓
configure once
     ↓
persistent build graph
```

Then most workers execute:

```text
incremental build target
```

not:

```text
cmake configure
build everything
```

If parallel worktrees require independent build directories, share as much immutable/cache state as possible:

* compiler cache,
* dependency downloads,
* generated immutable artifacts,
* configured baseline metadata where safe.

And only reconfigure when something affecting the CMake graph changed.

For example:

[
CMakeChanged(T)=false
\Rightarrow
NoFreshConfigure(T).
]

This should ideally be machine-enforced.

---

# 18. Build system questions belong in another deterministic broker

You now effectively need:

### Context Broker

```text
symbols
types
callers
owners
source relationships
```

### Build Broker

```text
target owning file
minimal build target
configure required?
existing build directory
test executable
dependency artifact
```

### Validation Broker

```text
run focused command
normalize result
extract first causal error
```

Again:

[
\text{do not ask Luna to figure these out}.
]

---

# 19. One manager can easily manage four workers—if you batch its work

I agree that one manager is preferable.

But don't wake it separately for every tiny event.

Imagine workers generate:

```text
W1: NEED_SCOPE(X)
W2: COMPLETE
W3: NEED_PREREQUISITE(Y)
W4: COMPLETE
```

The manager supervisor can collect pending semantic events and invoke one manager turn:

```text
Manager batch:
    decide W1
    review W2
    decide W3
    review W4
```

then publish four structured decisions.

So:

[
4\text{ events}
]

does not necessarily require:

[
4\text{ manager invocations}.
]

That's another significant source of token mining.

---

# 20. Make the manager event-driven rather than worker-synchronous

Bad architecture:

```text
worker
↓
manager
↓
worker
↓
manager
```

per worker.

Better:

```text
W1 ─┐
W2 ─┼→ manager inbox → one manager turn
W3 ─┤
W4 ─┘
```

The manager remains one authority.

But its inference is amortized across workers.

---

# 21. I would define three explicit performance ratios now

### Implementation yield

[
Y=
\frac{\text{accepted/checkpointed useful worker outputs}}
{\text{worker invocations}}.
]

You want this high.

### Control amplification

[
A_C=
\frac{\text{manager/replan/recovery invocations}}
{\text{accepted plan items}}.
]

You want this low.

### Parallel utilization

[
U_P=
\frac{\text{active worker slot-time}}
{N\times\text{wall time}}.
]

You want this high **only after (Y) becomes healthy**.

These three numbers will tell you almost everything.

---

# 22. The most revealing metric might actually be “negotiation-to-implementation ratio”

ACP now gives you enough data to measure:

[
R_N=
\frac{\text{control messages + recovery cycles}}
{\text{accepted source-changing episodes}}.
]

A little negotiation is good.

For example:

```text
NEED_CONTEXT
→ resolved
→ implementation
```

Excellent.

But:

```text
NEED_CONTEXT
→ reject
→ replan
→ NEED_CONTEXT
→ reject
→ replan
...
```

means your control system is malfunctioning.

---

# 23. I would revise the project's immediate priorities

Based strictly on the report you pasted, my ordering would be:

### P0 — Restore control-plane liveness

Fix the silent `SUPERVISOR_REVIEW_LEFT_UNCOMMITTED` state.

No invisible stalls.

### P0 — Make Context Broker requests succeed cheaply

Especially direct source/symbol/build/test neighbors.

Stop turning ordinary context acquisition into decomposition failure.

### P0 — Eliminate deterministic LLM recovery turns

Context repair, known graph cuts, known scope mechanics, state transitions.

### P1 — Increase useful first-pass yield

Measure why 72% of reviewed revisions are rejected and attack the largest categories.

### P1 — Introduce symbol-level capabilities/conflict analysis

Stop serializing unrelated work merely because it shares a file or broad directory.

### P1 — Publish several dependency-ready roots

Then activate your existing `N=4` capacity.

### P1 — Persistent/incremental build infrastructure

Drive 206 fresh configurations sharply downward.

### P2 — Manager batching

One manager inference for multiple pending worker events.

### P2 — More sophisticated parallel DAG scheduling

Conflict graph, critical-path awareness, perhaps priority scheduling.

---

# The deeper diagnosis

I don't think the harness is currently slow because your decomposition idea failed.

Rather, you've encountered the next layer of the problem:

[
\boxed{\text{decomposition itself needs an efficient runtime system}.}
]

You already solved:

> Don't give one model the whole project.

Then you discovered:

> The machinery enforcing the decomposition can itself become more expensive than the coding.

That's exactly what your report is showing:

```text
model work
      ↓
harness protocol
      ↓
context policy
      ↓
rejection
      ↓
replanning
      ↓
protocol
      ↓
...
```

So the next phase is not primarily "better intelligence."

It's **systems engineering of the agent runtime**.

You want the harness to behave more like a good OS scheduler:

[
\boxed{
\text{cheap fast path}
+
\text{rare expensive exception path}
+
\text{high resource utilization}
}
]

At the moment, it behaves more like an OS in which almost every syscall causes a page fault, permission exception, scheduler intervention, and process restart.

Fix that first.

Then your `N=4` worker pool should become genuinely powerful—and once it is stable, moving from 4 to 8 or 16 is mostly a throughput/economic decision rather than another architectural rewrite.
