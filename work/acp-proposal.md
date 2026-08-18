# Proposal: Agent Control Protocol for Dynamic, Token-Frugal Software Development

This proposal intentionally stays above source-code level. The coding agent should map it onto the existing harness implementation.

The central change is:

[
\boxed{\text{Replace assumed task readiness with negotiated task readiness}}
]

The current architecture is already a strong specification/compiler/recovery system whose goal is to give Luna a closed, bounded, verifiable change rather than the project-sized problem.  The weakness is that the system still tries too hard to establish that closure **before the worker actually encounters the implementation reality**.

The proposed design should preserve top-down authority while making information flow bidirectional.

---

## 1. Core architectural principle

Today the implicit assumption is approximately:

[
TaskReady(T)=true
]

followed by:

[
Manager\rightarrow Worker(T).
]

Change this to:

[
Manager\rightarrow Worker(T)
]

followed by the worker determining:

[
WorkerReady(T)=
\begin{cases}
READY\
NEEDS(X)
\end{cases}
]

The planner therefore proposes a task boundary.

The worker tests that boundary against reality.

The manager authorizes any change to the boundary.

The specification remains the highest authority.

So the fundamental rule becomes:

[
\boxed{
\text{The planner proposes;
the worker discovers;
the manager authorizes.
}
}
]

Communication is bidirectional.

Authority is not.

---

# 2. Introduce an Agent Control Protocol — ACP

Create a typed **Agent Control Protocol** between manager, workers, and deterministic services.

ACP is not free-form agent chat.

It is a project-management protocol.

Conceptually:

```text
                 Specification
                      │
                      ▼
                  Project DAG
                      │
                      ▼
                   Manager
              control authority
             ↙       ↑       ↘
          TASK     REQUEST    DAG UPDATE
           ↓         │
         Worker ─────┘
           │
           ├──────────────→ Context Broker
           │                    │
           ◄────────────────────┘
```

ACP should provide enough expressive power that an implementation problem does not have to be misrepresented as:

```text
COMPLETE
NEEDS_DECOMPOSITION
HARD_BLOCKED
```

The present harness already has this terminal-result concept. 

Those terminal states should remain, but most normal implementation discoveries should become **messages rather than terminal failures**.

---

# 3. Agents are ephemeral compute, never persistent services

This should be an explicit architectural invariant.

The persistent actors are:

```text
supervisor processes
filesystem/event state
repository indexes
context broker
scheduler
```

The model is invoked only when reasoning is required.

Conceptually:

```text
Worker waiting
    ≠
running Luna process
```

Instead:

```text
message arrives
      ↓
supervisor
      ↓
codex exec <saved-session>
      ↓
agent reasons
      ↓
agent writes message/result
      ↓
process exits
```

If another message arrives:

```text
supervisor
      ↓
codex exec <same-session-hash>
```

This preserves reasoning continuity without paying tokens for waiting.

Your existing architecture already embraces the important part of this idea: ordinary waiting is performed by token-free Bash supervisors rather than inference processes. 

ACP should make that principle universal.

The rule should be:

[
\boxed{
\text{No inference process exists unless there is useful reasoning to perform.}
}
]

---

# 4. Worker task acceptance becomes interactive

Do **not** add a mandatory separate “can you do this?” Luna invocation.

Instead the worker begins working immediately.

Its first responsibility is to verify the proposed boundary while implementing.

Possible paths:

```text
TASK
 │
 ▼
inspect supplied context
 │
 ├── sufficient ──────────→ WORK
 │
 ├── missing fact ────────→ REQUEST
 │
 ├── missing context ─────→ REQUEST
 │
 ├── missing authority ───→ REQUEST
 │
 ├── missing prerequisite → REQUEST
 │
 └── contradiction ───────→ CHALLENGE
```

If everything is correct, there is no extra message.

The common case remains cheap.

---

# 5. ACP worker messages

The precise vocabulary can evolve, but conceptually workers need messages such as:

```text
NEED_CONTEXT
NEED_SYMBOL
NEED_TYPE
NEED_CALLER
NEED_PRODUCER
NEED_CONSUMER
NEED_TEST
NEED_TEST_OWNER
NEED_BUILD_OWNER

NEED_SCOPE
NEED_CAPABILITY

NEED_PREREQUISITE
NEED_ACCEPTED_DECISION

VALIDATION_BLOCKED
CONTRACT_CONTRADICTION
SPECIFICATION_AMBIGUITY

SUGGEST_SPLIT
SUGGEST_REPLAN

CONTINUE
COMPLETE
```

Each request should carry structured evidence.

For example:

```text
type:
    NEED_SCOPE

requested:
    write capability for canonical representation producer

symbol:
    descriptor_encode

reason:
    consumer cannot satisfy assigned invariant because
    representation is produced upstream

evidence:
    exact observed producer/consumer relationship
```

The manager must be able to validate:

[
\operatorname{Need}(X)
]

rather than merely trusting Luna's assertion.

---

# 6. Manager responses

Manager ACP responses can include:

```text
GRANT_CONTEXT
GRANT_CAPABILITY
PROVIDE_FACT
PROVIDE_DECISION

CREATE_PREREQUISITE
WAIT_PREREQUISITE

SPLIT_TASK
REPLAN_TASK

DENY_REQUEST
CANCEL_TASK

ARCHITECTURE_REASSESSMENT
SPECIFICATION_CLARIFICATION
```

For example:

[
W:\operatorname{RequestAuthority}(X)
]

causes:

[
M:
\begin{cases}
Grant(X)\
CreatePrerequisite(X)\
Reject(X)\
Replan(T)
\end{cases}
]

The worker never self-expands its authority.

---

# 7. Make capabilities explicit

This naturally leads to capability-based worker authority.

A worker receives something like:

[
C_T=
{
read(A),
read(B),
write(C),
validate(V)
}.
]

During implementation it discovers that it needs:

[
write(D).
]

It sends:

[
RequestCapability(write(D),Evidence).
]

The manager determines whether the requested capability belongs to the legitimate semantic repair closure.

If yes:

[
C'_T=C_T\cup {write(D)}.
]

If not, the manager can create another task owning (D).

This keeps privilege decomposition aligned with task decomposition.

It also makes worker drift observable.

A worker repeatedly requesting unrelated capabilities becomes measurable evidence of either:

[
\text{bad decomposition}
]

or:

[
\text{worker drift}.
]

---

# 8. Context Broker becomes mandatory

This is probably one of the highest-value changes.

Many ACP requests must **never invoke a model**.

Examples:

```text
NEED_SYMBOL
NEED_TYPE
NEED_CALLER
NEED_CALLEE
NEED_TEST
NEED_BUILD_TARGET
NEED_OWNER
NEED_PRODUCER
NEED_CONSUMER
```

These should first go to a deterministic **Context Broker**.

Conceptually:

```text
Worker
   │
   │ NEED_CALLER(foo_submit)
   ▼
Context Broker
   │
   │ repository graph/index lookup
   ▼
foo_submit callers:
    module/a.c:...
    module/b.c:...
```

No manager inference.

No Luna repository exploration.

No repeated `grep`/`find`/file opening.

Your existing Context Closure already compiles definitions, interfaces, tests, ownership evidence and build targets into bounded worker context, and already has typed repair paths for incomplete closure. 

ACP should turn this from **precomputed context only** into:

[
\boxed{
\text{precomputed context}
+
\text{on-demand deterministic context}
}
]

The Context Broker should therefore be part of the control architecture rather than an optional optimization.

---

# 9. Manager should only see requests requiring judgment

The Context Broker handles facts.

The manager handles authority.

For example:

```text
NEED_CALLER(foo)
        ↓
Context Broker
```

but:

```text
NEED_SCOPE(write foo_owner)
        ↓
Manager
```

Similarly:

```text
NEED_TYPE
NEED_BUILD_OWNER
NEED_TEST
```

are primarily information problems.

While:

```text
Should I modify this producer?
Should the architecture change?
Does this become a prerequisite?
Is the worker drifting?
Does this conflict with the specification?
```

are management problems.

This could remove an enormous amount of model inference from the system.

---

# 10. Replace immutable execution DAG with immutable history + dynamic refinement

Do **not** make the entire DAG freely mutable.

That would destroy traceability.

Instead preserve:

[
G_0
]

as the original accepted decomposition and permit controlled append-only transformations:

[
G_0\rightarrow G_1\rightarrow G_2\rightarrow\dots
]

Each transformation must preserve history.

Suppose:

```text
A → B → C
```

and worker B discovers that producer X must first change.

Then:

```text
A → X → B → C
```

becomes the current executable graph.

But the system records:

```text
B originally assumed ready
B emitted NEED_PREREQUISITE(X)
manager validated request
X created
edge X → B inserted
```

This is extremely valuable information.

The dynamic DAG therefore becomes both:

[
\text{execution structure}
]

and:

[
\text{decomposition-quality evidence}.
]

---

# 11. Decomposition failures must remain first-class metrics

This point should be explicit.

Dynamic repair must **not hide bad decomposition**.

If Luna requests:

```text
NEED_SCOPE
NEED_CONTEXT
NEED_PREREQUISITE
SUGGEST_SPLIT
```

the harness may recover automatically, but the original planner decision should still receive a decomposition defect record.

Define something like:

[
D_f(T)
]

for decomposition failure characteristics of task (T).

Useful measurements include:

[
\text{initial context size}
]

versus:

[
\text{additional requested context}.
]

And:

[
R_{\text{context}}
==================

\frac{\text{additional context requested}}
{\text{initial context}}
]

or even:

[
R_{\text{repo}}
===============

\frac{\text{repository surface eventually requested}}
{\text{repository size}}.
]

If a supposedly small Luna leaf eventually requests two-thirds of the repository:

[
R_{\text{repo}}\approx0.67
]

then decomposition was catastrophically unsuccessful even if the worker ultimately completes.

That should be recorded.

Your documentation already recommends metrics such as first-pass Luna completion, context precision/recall, decomposition churn, actual versus predicted files/symbols, protocol overhead, retries, and architecture decision rediscovery. 

ACP gives you much richer telemetry for these measurements.

---

# 12. Treat ACP traffic as a new dataset

Every interaction should become durable structured telemetry:

```text
task
planner
leaf type
complexity estimate

message type
requested artifact
requested capability
manager decision
broker result

context before
context after
scope before
scope after

eventual completion
replan
defect escape
Oracle result
```

This lets you answer questions such as:

[
P(NEED_SCOPE\mid leaf_type)
]

[
P(NEED_CONTEXT\mid planner)
]

[
P(SUCCESS\mid n\ context\ requests)
]

[
P(REPLAN\mid complexity\ score)
]

and:

[
E[\text{tokens}\mid message\ pattern].
]

This is an exceptionally useful feedback signal for improving decomposition.

---

# 13. “Token mining” can become a real optimization metric

The informal name is actually useful.

Every deterministic answer that replaces model exploration effectively recovers inference budget.

Define:

[
T_{\text{saved}}
================

## T_{\text{estimated model discovery}}

T_{\text{ACP/broker processing}}.
]

Examples:

```text
symbol lookup
caller lookup
build-owner lookup
test lookup
dependency lookup
type definition retrieval
```

should trend toward essentially zero model tokens.

Track:

[
\boxed{\text{model tokens per accepted semantic obligation}}
]

as the primary economic measure.

And separately:

[
\boxed{\text{tokens spent on repository discovery}}
]

which ideally approaches:

[
0.
]

That would quantify the “token mining” effect.

---

# 14. Add batched parallel workers

The current harness deliberately serializes execution through a single active plan item. 

ACP makes a transition to parallel workers more natural.

Keep:

[
\boxed{\text{one manager}}
]

but permit:

[
W_1,W_2,\ldots,W_N
]

simultaneously.

Default:

[
N=4.
]

And define:

[
N=0
]

as maximum scheduler-selected parallelism.

I would interpret `0` as **no configured worker-count ceiling**, not literally infinite launch.

Machine capacity and quota safety still impose physical limits.

Architecture:

```text
                  Manager
              /      |      \
             /       |       \
           W1       W2       W3       W4
            │        │        │        │
            └──── ACP / Context Broker ┘
```

The manager remains single because:

[
\text{single authority}
\Rightarrow
\text{unambiguous decisions}.
]

Multiple managers can come much later, if ever.

---

# 15. Parallel workers need isolated mutation domains

Your current documentation already correctly identifies that parallel DAG execution requires isolated workspaces, immutable common bases, checked disjoint authority, independent builds, deterministic integration and post-merge health gates. 

ACP should build on that rather than bypass it.

Worker parallelism therefore means:

[
\operatorname{Independent}(W_i,W_j)
]

or explicit manager-owned integration.

The manager must never accidentally grant:

[
write(X)
]

to two concurrently running workers unless the project explicitly defines how those writes are reconciled.

---

# 16. Single manager, many workers

I agree strongly with keeping a single manager initially.

Think:

[
Manager=\text{control-plane authority}
]

rather than another coding worker.

Its responsibilities are:

```text
schedule
validate worker requests
grant/reject authority
create prerequisites
update executable DAG
detect worker drift
coordinate integration
preserve specification authority
```

It should not spend its time doing simple source discovery.

That's the Context Broker's job.

Nor should the manager remain running.

It too is ephemeral inference:

```text
manager message/event
      ↓
manager supervisor
      ↓
codex exec <manager-session>
      ↓
decision
      ↓
exit
```

One **logical manager**, not one continuously running model process.

---

# 17. Worker drift detection becomes much easier

Manager validation of requests is important.

Suppose worker receives:

```text
implement parser error handling
```

and subsequently requests:

```text
write database/
write scheduler/
write network/
```

ACP provides direct evidence that something is wrong.

The manager can compare:

[
RequestedCapability
]

against:

[
SemanticClosure(Task).
]

Conceptually:

[
distance(Task,X)>D_{\max}
\Rightarrow
\operatorname{SuspectDrift}.
]

The first version need not calculate a sophisticated graph distance.

A manager judgment is sufficient.

But every decision should be recorded for later analysis.

---

# 18. Do not initially impose aggressive negotiation limits

I agree with your correction here.

The current problem appears to be **millions of tokens wasted through uncontrolled repository exploration**.

Against that baseline:

```text
Worker: NEED_X
Manager: GRANT
Worker: NEED_Y
Broker: HERE
Worker: COMPLETE
```

is extremely cheap.

So ACP v1 should prioritize:

[
\text{correctness}
+
\text{observability}
+
\text{token displacement}
]

over minimizing message count.

Record the negotiation traffic first.

After sufficient real projects, determine empirically whether negotiation itself becomes expensive.

Only then introduce negotiation budgets.

---

# 19. Separate control plane from data plane

Make this a formal architectural distinction.

### Control plane

ACP messages:

```text
TASK
REQUEST
GRANT
DENY
WAIT
SPLIT
REPLAN
CANCEL
COMPLETE
```

### Data plane

Engineering objects:

```text
source code
patches
repository context
symbol definitions
tests
build artifacts
validation results
architecture contracts
evidence
commits
```

An ACP control message should generally reference data-plane artifacts by durable identity rather than copying large content into every message.

That should itself reduce tokens.

---

# 20. Proposed runtime state machine

The conceptual worker lifecycle becomes:

```text
                         ┌──────────────┐
                         │ TASK_READY   │
                         └──────┬───────┘
                                │
                                ▼
                         ┌──────────────┐
                         │   WORKING    │
                         └──────┬───────┘
                                │
                  ┌─────────────┼──────────────┐
                  │             │              │
                  ▼             ▼              ▼
            NEED_CONTEXT   NEED_AUTHORITY   NEED_PREREQ
                  │             │              │
                  └──────┬──────┴──────┬───────┘
                         ▼             ▼
                   Broker/Manager   DAG update
                         │             │
                         └──────┬──────┘
                                ▼
                             RESUME
                                │
                                ▼
                            WORKING
                                │
                    ┌───────────┼───────────┐
                    ▼           ▼           ▼
                 COMPLETE     SPLIT      CHALLENGE
```

No model waits at any state.

Only supervisors wait.

---

# 21. The project DAG now has two kinds of edges

This is worth formalizing.

### Planned edges

Created during decomposition:

[
E_P.
]

### Discovered edges

Created during implementation negotiation:

[
E_D.
]

Therefore:

[
G_t=(V,E_P\cup E_D).
]

This lets you measure:

[
\frac{|E_D|}{|E_P|}.
]

A high value can indicate weak initial decomposition.

Similarly new nodes:

[
V_D
]

created from worker discoveries become another decomposition-quality signal.

An excellent planner should eventually drive:

[
\frac{|V_D|+|E_D|}
{|V|+|E|}
\rightarrow 0
]

for familiar project classes.

But the system remains robust even when this ratio is temporarily high.

---

# 22. This solves an important philosophical problem in the current harness

The present architecture tries to achieve:

[
\text{perfect foresight before execution}.
]

That's fundamentally expensive.

The proposed architecture instead aims for:

[
\boxed{
\text{sufficient foresight}
+
\text{cheap correction}
}
]

That is likely a much better engineering tradeoff.

Instead of making Sol/Terra/Luna solve the entire semantic closure problem in advance, let actual implementation reveal missing constraints.

Then route those discoveries through cheap deterministic infrastructure whenever possible.

---

# 23. Recommended first implementation scope

I would keep the first ACP version intentionally small.

Implement only:

```text
TASK
NEED_CONTEXT
NEED_SCOPE
NEED_PREREQUISITE
SUGGEST_SPLIT
COMPLETE
CANCEL
```

plus:

```text
GRANT_CONTEXT
GRANT_SCOPE
CREATE_PREREQUISITE
DENY
SPLIT
```

Make the Context Broker mandatory for deterministic requests.

Add worker batches with:

```text
default N = 4
N = 0 → maximum permitted parallelism
```

Keep one logical manager.

Keep all agents ephemeral.

Record every ACP transaction.

Do not initially build consensus management, sophisticated negotiation budgets, automated learning, or complicated distributed scheduling.

Get the basic loop working end-to-end.

---

# 24. Acceptance criteria for the redesign

The coding agent should consider the ACP redesign successful when the following scenario works reliably:

```text
1. Planner creates task B.

2. Manager dispatches B to Luna.

3. Luna begins implementation.

4. Luna discovers missing producer X.

5. Luna emits NEED_PREREQUISITE(X).

6. Manager validates the claim.

7. Manager creates node X and dependency:
       X → B

8. Luna B exits; no token-consuming process waits.

9. Scheduler runs X, potentially alongside other independent workers.

10. X completes and is accepted.

11. Supervisor resumes B using its saved session identity.

12. B consumes the newly accepted producer.

13. B completes.

14. All original and discovered graph mutations,
    messages, requests, decisions, evidence, costs,
    and decomposition defects remain auditable.
```

If that works, the harness has crossed an important architectural boundary.

---

# Final architectural statement for the coding agent

I would put this near the top of the implementation proposal:

> **The harness must no longer require perfect task closure before worker execution. Initial decomposition establishes a bounded proposal, not an infallible prediction. Workers may discover missing context, capabilities, prerequisites, or decomposition seams and communicate them through a typed Agent Control Protocol. Deterministic repository questions are answered by a mandatory Context Broker; authority-changing requests are adjudicated by one logical manager. All model processes remain ephemeral and are launched only when reasoning is required, with supervisors owning all waiting and session resumption. The project DAG retains immutable history while permitting audited append-only runtime refinement. Worker negotiation is therefore both a recovery mechanism and a first-class measurement of decomposition quality. Independent dependency-ready workers may execute in bounded parallel batches, initially four by default, while one manager retains project authority.**

This changes the architecture from:

[
\boxed{\text{plan perfectly, then execute}}
]

to:

[
\boxed{
\text{plan}
\rightarrow
\text{execute}
\leftrightarrow
\text{discover}
\leftrightarrow
\text{negotiate}
\rightarrow
\text{refine}
}
]

while still preserving:

[
\boxed{\text{Specification}>\text{Manager}>\text{Worker authority}.}
]

I think this is a substantially more natural foundation for the kind of enormous, low-cost software-production system you're trying to build. It also directly addresses one of the latest architecture document's own P0 weaknesses: general semantic repair closure is not yet proven, and workers can currently discover valid repair seams outside their assigned authority. 
