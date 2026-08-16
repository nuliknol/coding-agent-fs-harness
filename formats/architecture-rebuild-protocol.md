# Periodic Architecture Rebuild Protocol for Agent-Coded Software Systems

## 1. Purpose

This document defines a periodic architecture-rebuild procedure for software systems developed primarily by coding agents.

The purpose of an architecture rebuild is **not to rewrite the software**.

Its purpose is to periodically transform the existing implementation into a structure that is easier for both humans and agents to reason about, modify, test, and extend.

The rebuild must improve four properties in particular:

1. **Architecture as a reasoning index**
   The architecture should allow an agent to rapidly determine where a requirement belongs and which parts of the system are irrelevant.

2. **Complexity decomposition**
   Large behaviors should be represented as explicit, bounded subproblems with clear interfaces and dependencies.

3. **Per-module structural quality**
   Each module should have a coherent responsibility, small reasoning surface, explicit invariants, and minimal unnecessary coupling.

4. **Change locality**
   A conceptually local feature should require conceptually local modifications.

The architecture rebuild should therefore minimize the amount of system state an agent must understand simultaneously.

A useful objective is:

[
\boxed{
\text{Minimize reasoning scope required per change}
}
]

while preserving:

[
\boxed{
\text{behavior} +
\text{correctness} +
\text{performance} +
\text{maintainability}
}
]

---

# 2. Fundamental Principle

Software architecture is not merely organization of source code.

For an agent, architecture is a **search-space reduction mechanism**.

Given a requested change (R), the architecture should make it possible to derive:

[
R
\rightarrow
\text{subsystem}
\rightarrow
\text{module set}
\rightarrow
\text{interfaces}
\rightarrow
\text{implementation locations}
\rightarrow
\text{verification}
]

without searching the entire repository.

The desired property is:

[
|\text{RelevantCode}(R)| \ll |\text{Repository}|
]

An architecture rebuild is successful when future agents can eliminate most of the repository from consideration before implementation begins.

---

# 3. Architecture Rebuild Is Not a Rewrite

Agents performing this procedure must distinguish between:

### Architecture rebuild

A controlled transformation of the existing system that preserves externally required behavior while improving structural organization.

and:

### Software rewrite

Replacement of substantial existing functionality with newly implemented functionality.

A periodic architecture rebuild SHOULD reuse proven implementation whenever possible.

The default operation is:

[
\text{move}
\rightarrow
\text{separate}
\rightarrow
\text{rename}
\rightarrow
\text{encapsulate}
\rightarrow
\text{simplify}
\rightarrow
\text{deduplicate}
]

rather than:

[
\text{delete}
\rightarrow
\text{reimplement}
]

Reimplementation is allowed only when the existing implementation itself prevents architectural correction.

---

# 4. When an Architecture Rebuild Must Be Triggered

Do not rely exclusively on calendar intervals.

Architecture rebuilds should be triggered primarily by **structural degradation indicators**.

A rebuild SHOULD be considered when one or more of the following conditions occur.

## 4.1 Change fan-out increases

A conceptually small feature repeatedly requires modifications across many unrelated files or modules.

Measure:

[
F_{\text{change}}
=================

\frac{\text{modules modified}}
{\text{conceptual responsibilities changed}}
]

Increasing (F_{\text{change}}) indicates architectural leakage.

---

## 4.2 Agents repeatedly search the same large areas

If coding agents frequently have to inspect many files before locating the correct implementation point, the architectural reasoning index has weakened.

Examples:

* searching dozens of files for ownership of a concept;
* repeatedly tracing the same call paths;
* finding several implementations of apparently identical concepts;
* inability to identify authoritative state ownership.

---

## 4.3 Prompt/context requirements increase

Track approximately how much repository context is required to perform common modifications.

If similar changes require progressively more context, architecture quality is declining.

A desirable trend is:

[
C_{\text{required}}(t) \approx \text{constant}
]

even while repository size grows.

Repository size may increase by (10\times), while the context necessary for a local task should ideally remain nearly constant.

---

## 4.4 Cross-module coupling increases

Trigger a rebuild if modules increasingly:

* access each other's internal state;
* bypass public interfaces;
* know implementation details of unrelated modules;
* import low-level components across subsystem boundaries;
* share mutable global state;
* depend cyclically on each other.

---

## 4.5 Duplicate semantics appear

Duplicate code is not the only important duplication.

More dangerous is **duplicate meaning**.

Examples:

* two definitions of what constitutes an active user;
* three different representations of task state;
* two authorization checks implementing slightly different policies;
* multiple interpretations of the same configuration field;
* different modules independently deriving the same state.

This indicates missing semantic ownership.

---

## 4.6 Conditional complexity grows

Repeated patterns such as:

```text
if mode == A ...
else if mode == B ...
else if subsystem == C ...
else if old_behavior ...
```

often indicate that architectural boundaries no longer represent the conceptual structure of the system.

Conditional growth should trigger investigation into missing state machines, strategies, policies, dispatch layers, or object boundaries.

---

## 4.7 Agent modifications produce collateral regressions

If agents frequently fix one subsystem while breaking another, investigate whether:

[
\text{implementation dependency}

>

\text{declared architectural dependency}
]

Undocumented coupling is a strong rebuild signal.

---

## 4.8 Repository navigation becomes ambiguous

Examples:

* unclear filenames;
* several plausible locations for new functionality;
* very large generic utility directories;
* modules named `common`, `helpers`, `misc`, or `utils` accumulating unrelated functionality;
* multiple competing abstraction layers;
* unclear subsystem roots.

---

# 5. Recommended Rebuild Frequency

Use three levels of architecture maintenance.

## Level 1 — Continuous Local Refactoring

Performed during ordinary feature work.

Scope:

[
1\text{–}3 \text{ modules}
]

Purpose:

* preserve local coherence;
* remove newly introduced duplication;
* keep interfaces clean;
* prevent obvious architectural debt.

---

## Level 2 — Periodic Architecture Rebuild

Performed after a meaningful amount of development or when degradation metrics trigger it.

Scope:

[
\text{one subsystem or major architectural region}
]

The rebuild may modify module boundaries, dependency direction, APIs, state ownership, directory organization, and internal abstractions.

---

## Level 3 — Global Architecture Reassessment

Performed rarely.

Scope:

[
\text{entire system}
]

Purpose:

* verify that major subsystem boundaries still correspond to the real problem domain;
* identify architectural layers that no longer serve a purpose;
* detect systemic coupling or semantic duplication;
* rebuild the global architectural map.

A global reassessment does **not** imply globally rewriting implementation.

---

# 6. Required Inputs Before Rebuilding

Before modifying architecture, the agent MUST construct a model of the current system.

The following artifacts should exist or be generated.

## 6.1 Module graph

Represent modules as:

[
G_M=(V_M,E_M)
]

where:

* (V_M) = modules;
* (E_M) = dependency relationships.

Classify dependencies where possible:

* calls;
* imports;
* reads;
* writes;
* ownership;
* lifecycle;
* configuration;
* event publication;
* event consumption.

---

## 6.2 Responsibility map

For every major module record:

```text
Module:
Primary responsibility:
Inputs:
Outputs:
State owned:
State read:
Public interface:
Dependencies:
Dependents:
Important invariants:
Primary tests:
```

A module for which the primary responsibility cannot be described concisely is automatically a refactoring candidate.

---

## 6.3 System concept map

Identify major domain concepts independently of source-code structure.

For example:

```text
User
Session
Authentication
Authorization
Job
Scheduler
Worker
Storage
Configuration
Network connection
Transaction
```

Then map:

[
\text{Domain concept}
\rightarrow
\text{authoritative implementation}
]

Every important concept should have a clearly identifiable owner.

---

# 7. Architecture as a Reasoning Index

## 7.1 Objective

Architecture should answer the question:

> Given requirement (R), where should reasoning begin?

An effective architecture allows an agent to transform:

[
R
]

into a very small candidate set:

[
M(R)={m_1,m_2,\ldots,m_k}
]

where:

[
k \ll |V_M|
]

---

# 8. Improving the Reasoning Index

During every rebuild, explicitly perform the following operations.

## 8.1 Give every domain concept an owner

There should normally be one authoritative location for:

* representation;
* validation;
* state transitions;
* invariants;
* persistence policy;
* domain-specific operations.

Avoid:

[
\text{concept}
\rightarrow
{A,B,C,D,E}
]

when ownership can instead be:

[
\text{concept}
\rightarrow A
]

with other modules depending on (A).

---

## 8.2 Make directory structure semantic

Directory organization should describe the architecture rather than development history.

Prefer:

```text
scheduler/
storage/
compiler/
network/
authorization/
```

over:

```text
new/
old/
misc/
helpers/
code2/
experimental/
```

A new agent should obtain useful architectural information simply by inspecting the repository tree.

---

## 8.3 Eliminate ambiguous implementation locations

For each major capability ask:

> If an agent were instructed to modify this capability, would there be one obvious place to begin?

If several equally plausible starting locations exist, improve the architecture.

---

## 8.4 Make dependency direction predictable

Dependencies should preferably form a directional graph rather than an arbitrary network.

For example:

[
\text{UI}
\rightarrow
\text{application logic}
\rightarrow
\text{domain}
\rightarrow
\text{infrastructure interfaces}
]

Actual architecture may differ, but dependency direction must be explainable.

Cycles require explicit justification.

---

## 8.5 Separate policy from mechanism

A particularly valuable reasoning-index improvement is separating:

### Mechanism

What the system can do.

from:

### Policy

When and why it should do it.

For example:

```text
Storage mechanism
	!=
Retention policy

Thread mechanism
	!=
Scheduling policy

Transport mechanism
	!=
Retry policy
```

Mixing policy and mechanism greatly enlarges the reasoning surface for changes.

---

# 9. Measure Reasoning-Index Quality

For representative tasks (R_i), estimate:

[
I(R_i)
======

\frac{|\text{Relevant modules}|}
{|\text{Modules initially considered}|}
]

Lower is better.

Alternatively define index efficiency:

[
E_{\text{index}}(R_i)
=====================

1-
\frac{|\text{Relevant modules}|}
{|\text{Modules searched}|}
]

The precise equation is less important than tracking whether repository navigation is becoming easier or harder.

Maintain a small benchmark set of representative modification tasks.

Examples:

```text
Change authentication expiration.
Add scheduler priority.
Modify serialization format.
Add new storage backend.
Change CLI option parsing.
Add new network message type.
```

After architectural rebuilds, agents should reach the relevant implementation with less exploration.

---

# 10. Complexity Decomposition

Architecture rebuilding MUST inspect not only module boundaries but also the structure of reasoning required within those modules.

The desired transformation is:

[
P
\rightarrow
{P_1,P_2,\ldots,P_n}
]

where each (P_i):

* has a narrow purpose;
* has explicit inputs;
* has explicit outputs;
* has explicit invariants;
* can be tested independently;
* requires limited external context.

---

# 11. Decomposition Procedure

For each subsystem:

## Step 1 — Identify responsibilities

List everything the subsystem currently does.

Do not infer responsibilities from filenames alone.

Inspect actual behavior.

---

## Step 2 — Construct responsibility dependencies

Represent:

[
R_i \rightarrow R_j
]

when responsibility (R_i) fundamentally depends on (R_j).

---

## Step 3 — Separate unrelated responsibilities

Two responsibilities should generally not occupy the same module merely because they were historically implemented together.

Ask:

> Would these two behaviors change for the same reasons?

If not, consider separating them.

This is a powerful test of module cohesion.

---

## Step 4 — Identify state ownership

For every mutable state variable or structure determine:

```text
Who creates it?
Who owns it?
Who may modify it?
Who may observe it?
What invariants constrain it?
What destroys it?
```

State without clear ownership is architectural debt.

---

## Step 5 — Identify transformations

Prefer explicit transformation pipelines where appropriate:

[
A
\rightarrow B
\rightarrow C
\rightarrow D
]

over functions that simultaneously:

* validate;
* transform;
* mutate;
* persist;
* notify;
* log;
* perform policy decisions.

---

## Step 6 — Expose contracts

Every important boundary should expose enough information that an agent modifying one side does not need to inspect the implementation of the other side.

This is essential.

A good interface functions as a **reasoning firewall**.

---

# 12. Reasoning Firewalls

A reasoning firewall is a module boundary beyond which implementation knowledge should normally be unnecessary.

If module (A) depends on module (B):

[
A\rightarrow B
]

then modifying (A) should usually require knowledge of:

[
\text{Interface}(B)
]

rather than:

[
\text{Implementation}(B)
]

Every rebuild should explicitly search for failed reasoning firewalls.

Symptoms include:

* callers depending on internal data structures;
* duplicated validation outside the owning module;
* callers knowing execution order that should be private;
* external modules modifying owned state;
* tests requiring internal implementation assumptions.

---

# 13. Per-Module Refactoring Procedure

Every module touched during an architecture rebuild should undergo the following inspection.

## 13.1 Define the module in one sentence

The module should have a statement of the form:

> This module is responsible for X.

If the sentence requires repeated use of “and,” the module may contain several responsibilities.

---

## 13.2 Identify the public surface

List all externally visible functions, types, events, and state.

Ask whether every exposed element must actually be public.

Minimize:

[
S_{\text{public}}
]

because every public element becomes part of the reasoning surface for other modules.

---

## 13.3 Remove accidental coupling

Search for dependencies that exist due to implementation convenience rather than conceptual necessity.

---

## 13.4 Remove dead abstractions

An abstraction is not automatically beneficial.

Remove abstractions that:

* have one implementation and no likely variation;
* merely rename another interface;
* provide no semantic compression;
* force agents through unnecessary indirection;
* exist only because an earlier design anticipated functionality that never appeared.

Architecture should minimize both:

[
\text{under-abstraction}
]

and:

[
\text{over-abstraction}
]

---

## 13.5 Remove semantic duplication

Search beyond literal duplicated code.

Look for duplicated:

* conditions;
* state definitions;
* validation;
* conversions;
* policy;
* derived values;
* error semantics;
* lifecycle rules.

Select one authoritative implementation.

---

## 13.6 Simplify control flow

Reduce unnecessary nesting and scattered conditional behavior.

Where appropriate convert implicit state logic into explicit state machines.

Instead of:

[
\text{many independent flags}
]

prefer an explicit state representation when the domain truly represents mutually constrained states.

---

## 13.7 Reduce hidden temporal coupling

Watch for code requiring operations to be called in undocumented sequences:

```text
initialize A
then configure B
then call C
but only after D
```

If order matters, encode it explicitly through:

* types;
* state representation;
* lifecycle API;
* orchestration layer;
* explicit state machine.

Do not leave temporal invariants purely in programmer memory.

---

## 13.8 Minimize module context requirements

Ask:

> How much unrelated information must an agent understand before safely modifying this module?

Reduce that amount.

---

# 14. Preserve and Strengthen Invariants

A rebuild should make important assumptions more explicit.

Convert assumptions from:

[
\text{tribal knowledge}
]

into:

[
\text{machine-checkable constraints}
]

where practical.

Use:

* types;
* assertions;
* validators;
* static checks;
* tests;
* contracts;
* state machines;
* database constraints;
* compile-time constraints.

Agents work much better when invalid states are structurally difficult to construct.

---

# 15. Optimize Change Locality

For each representative requirement determine:

[
L(R)=|\text{modules requiring modification}|
]

A healthy architecture minimizes (L(R)) for conceptually local changes.

Do not optimize blindly for the smallest number of files.

Sometimes multiple files represent legitimate layers.

Instead optimize:

[
\boxed{
\text{architecturally necessary change surface}
}
]

Remove **accidental change propagation**.

---

# 16. Architectural Entropy

Treat architectural disorder as something that accumulates continuously.

Define conceptually:

[
H_A =
H_{\text{coupling}}
+
H_{\text{duplication}}
+
H_{\text{ambiguity}}
+
H_{\text{hidden state}}
+
H_{\text{dependency}}
+
H_{\text{obsolete abstractions}}
]

Feature implementation tends to increase (H_A).

Refactoring reduces it.

Architecture maintenance should attempt to maintain:

[
\frac{dH_A}{dt}\approx0
]

rather than allowing architectural entropy to accumulate indefinitely.

Periodic architecture rebuilds are the mechanism for correcting accumulated entropy that local refactoring failed to remove.

---

# 17. Context-Efficiency Optimization

Because this project is developed by agents, explicitly optimize architecture for bounded context.

For every subsystem, maintain a compact architectural description containing:

```text
Purpose
Owned concepts
Public interface
State ownership
Dependencies
Dependents
Important invariants
Primary execution paths
Important tests
Known performance constraints
```

An agent beginning work on that subsystem should be able to understand its architectural role without reading its entire implementation.

Documentation should describe **stable semantic structure**, not duplicate implementation details.

---

# 18. Agent Work-Packet Design

Architecture should make it possible to give an agent a bounded work packet.

A high-quality work packet should contain:

[
W=
{
\text{goal},
\text{scope},
\text{interfaces},
\text{invariants},
\text{constraints},
\text{tests}
}
]

The agent should not ordinarily need the entire repository.

During an architecture rebuild, ask:

> Could future work on this subsystem be assigned as an isolated work packet?

If not, identify why.

The answer often exposes hidden coupling.

---

# 19. Test Architecture, Not Only Implementation

Tests should verify architectural properties in addition to functional behavior.

Where practical, test:

* forbidden dependency directions;
* interface boundaries;
* state ownership;
* serialization contracts;
* public API behavior;
* subsystem isolation;
* lifecycle invariants;
* allowed state transitions.

The rebuild should strengthen tests before making high-risk structural changes.

---

# 20. Rebuild Execution Order

The agent MUST perform architecture rebuilding in the following order.

## Phase 1 — Observe

Do not modify code yet.

Construct:

* module graph;
* responsibility map;
* state ownership map;
* important execution paths;
* architectural problems list.

---

## Phase 2 — Diagnose

Classify problems.

Suggested categories:

```text
RESPONSIBILITY_DUPLICATION
SEMANTIC_DUPLICATION
EXCESSIVE_COUPLING
DEPENDENCY_CYCLE
UNCLEAR_STATE_OWNERSHIP
POOR_CHANGE_LOCALITY
AMBIGUOUS_MODULE_OWNERSHIP
LEAKY_ABSTRACTION
OVER_ABSTRACTION
UNDER_ABSTRACTION
HIDDEN_TEMPORAL_COUPLING
EXCESSIVE_PUBLIC_SURFACE
ARCHITECTURAL_DEAD_CODE
CONTEXT_INEFFICIENCY
TEST_COUPLING
```

---

## Phase 3 — Design Target Architecture

Before modifying implementation, produce the proposed target structure.

For every significant change specify:

```text
Current structure:
Problem:
Target structure:
Reason:
Expected reasoning improvement:
Affected modules:
Migration strategy:
Required tests:
```

---

## Phase 4 — Establish behavioral baseline

Run all relevant tests.

Record failures that already exist.

Do not attribute pre-existing failures to the rebuild.

For critical subsystems add characterization tests when current behavior is insufficiently specified.

---

## Phase 5 — Refactor Incrementally

Perform transformations in small graph-preserving steps.

Preferred order:

1. add or strengthen tests;
2. introduce target interface;
3. migrate callers;
4. move ownership;
5. simplify implementation;
6. remove obsolete path;
7. remove compatibility scaffolding;
8. verify architecture.

Do not combine unrelated architectural transformations into one change merely because they occur in the same rebuild.

---

## Phase 6 — Recompute Architecture

After modification regenerate or inspect:

* dependency graph;
* module ownership;
* cycles;
* API surfaces;
* duplicate concepts;
* state ownership.

Do not assume that the intended architecture equals the resulting architecture.

---

# 21. Before/After Architecture Evaluation

Every rebuild MUST include an explicit before/after comparison.

Evaluate at minimum:

| Property                             | Before | After |
| ------------------------------------ | -----: | ----: |
| Module count                         |        |       |
| Dependency edges                     |        |       |
| Dependency cycles                    |        |       |
| Large modules                        |        |       |
| Duplicate concept owners             |        |       |
| Cross-subsystem writes               |        |       |
| Public API surface                   |        |       |
| Representative change fan-out        |        |       |
| Required context for benchmark tasks |        |       |
| Architectural violations             |        |       |

Not every value must decrease.

For example, decomposition may increase module count.

The important objective is reduction in **reasoning complexity**, not minimization of arbitrary structural counts.

---

# 22. Architecture Benchmark Tasks

Maintain a permanent set of realistic architectural navigation tasks.

Examples:

```text
Where is X state owned?

What modules must change to add Y?

Where is policy Z implemented?

Which modules are allowed to mutate object A?

What is the lifecycle of subsystem B?

How would a new implementation of interface C be added?

Which subsystem validates D?

What tests prove invariant E?
```

Periodically give these questions to a fresh agent with no prior project context.

Measure:

* number of files inspected;
* number of incorrect hypotheses;
* amount of context consumed;
* time/steps until correct subsystem identification.

This directly tests architecture as a reasoning index.

---

# 23. Fresh-Agent Test

One of the strongest architecture tests is a new agent.

After a significant rebuild, give a fresh agent:

1. repository root;
2. architecture documentation;
3. one representative modification task.

Do not provide historical conversational context.

Observe whether the agent can derive:

[
\text{requirement}
\rightarrow
\text{correct subsystem}
\rightarrow
\text{correct files}
\rightarrow
\text{correct tests}
]

A system that only works well when an agent has accumulated enormous conversational history has weak architectural discoverability.

---

# 24. Detect Architecture Documentation Drift

Architecture documentation must be treated as an index into the actual implementation.

Therefore:

[
\text{DocumentedArchitecture}
\approx
\text{ImplementedArchitecture}
]

After every rebuild check:

* module names;
* ownership;
* dependency direction;
* public interfaces;
* lifecycle;
* invariants.

Delete obsolete documentation rather than preserving historical descriptions as if they were current.

---

# 25. Remove Historical Scaffolding

Periodic rebuilds should search specifically for artifacts that were useful during development but are no longer architecturally necessary.

Examples:

* deprecated APIs;
* compatibility wrappers;
* transitional adapters;
* experimental interfaces;
* old representations;
* temporary feature flags;
* duplicate migration paths;
* obsolete configuration options;
* unused extension hooks.

Temporary architecture has a tendency to become permanent unless explicitly removed.

---

# 26. Avoid Premature Genericization

Agents frequently respond to growing complexity by creating generic frameworks.

Do not automatically generalize.

Generalization is justified when several concrete cases expose a stable common structure.

Prefer:

[
\text{concrete cases}
\rightarrow
\text{observed commonality}
\rightarrow
\text{abstraction}
]

rather than:

[
\text{predicted future complexity}
\rightarrow
\text{large generic framework}
]

An unused abstraction increases reasoning cost.

---

# 27. Optimize Semantic Density

A good module should encode a large amount of relevant domain meaning with a small amount of architectural explanation.

Prefer names such as:

```text
Scheduler
TransactionManager
AuthorizationPolicy
ObjectStore
ConnectionPool
```

when these accurately represent ownership.

Avoid structures whose names communicate implementation accidents rather than meaning.

The architecture should operate as a compressed semantic representation of the program.

---

# 28. Architecture Should Mirror the Problem Graph

The module graph should approximately reflect the conceptual graph of the problem domain.

Let:

[
G_P=\text{problem-domain dependency graph}
]

and:

[
G_S=\text{software dependency graph}
]

A strong architecture attempts to maintain structural correspondence:

[
G_S \approx G_P
]

If two concepts are independent in the problem domain but tightly coupled in software, investigate why.

If one concept in the problem domain is fragmented across many unrelated modules, investigate why.

Architecture rebuilds should reduce unnecessary divergence between these graphs.

---

# 29. Minimize Architectural Surprise

A developer or agent should be able to make reasonable predictions from architecture.

Examples:

* storage functionality belongs under storage;
* scheduler state is owned by scheduler;
* authorization rules are not hidden in UI code;
* parsing code does not silently perform persistence;
* utility libraries do not own domain policy.

Architectural predictability dramatically reduces search.

---

# 30. Refactoring Stop Condition

Do not refactor indefinitely.

A rebuild is complete when:

1. identified high-value architectural problems have been addressed;
2. tests pass;
3. ownership is unambiguous;
4. dependency direction is acceptable;
5. major semantic duplication has been removed;
6. representative changes have bounded reasoning scopes;
7. architecture documentation matches implementation;
8. further changes offer low reasoning benefit relative to risk.

The objective is not architectural perfection.

The objective is:

[
\boxed{
\text{maximum future reasoning reduction per unit of refactoring effort}
}
]

---

# 31. Rebuild Priority Function

When many architectural problems exist, prioritize them approximately by:

[
P_i=
\frac{
F_i
\times
R_i
\times
C_i
}{
M_i
}
]

where:

* (F_i) = frequency with which the affected area changes;
* (R_i) = reasoning complexity caused by the problem;
* (C_i) = collateral-change or failure cost;
* (M_i) = migration cost.

High-frequency architectural friction should normally be fixed before low-frequency aesthetic problems.

---

# 32. Mandatory Agent Rules During Rebuilds

Agents performing architecture work MUST obey the following rules.

### Rule 1

Do not modify architecture before understanding current behavior.

### Rule 2

Do not confuse architectural improvement with code beautification.

### Rule 3

Every architectural change must state which reasoning problem it solves.

### Rule 4

Prefer explicit ownership over shared responsibility.

### Rule 5

Prefer narrow interfaces over cross-module implementation knowledge.

### Rule 6

Prefer dependency elimination over dependency documentation.

### Rule 7

Prefer machine-enforced invariants over comments.

### Rule 8

Prefer removal of obsolete abstractions over preservation for hypothetical future use.

### Rule 9

Do not create abstractions without demonstrated semantic value.

### Rule 10

Preserve behavior unless behavior change is explicitly part of the specification.

### Rule 11

Do not perform uncontrolled repository-wide rewrites.

### Rule 12

Every rebuild must leave the repository easier for the **next agent**, not merely understandable to the agent that performed the rebuild.

---

# 33. Required Rebuild Report

At the end of every periodic architecture rebuild, produce the following report.

## Architecture Rebuild Report

### Scope

```text
Subsystems analyzed:
Subsystems modified:
Files modified:
```

### Problems discovered

For every important problem:

```text
Problem:
Category:
Affected components:
Reasoning cost:
Operational risk:
```

### Changes performed

```text
Architectural change:
Old structure:
New structure:
Reason:
```

### Reasoning-index improvements

```text
Requirements that now map more directly to implementation:
Ambiguous ownership removed:
Search paths eliminated:
Cross-module knowledge removed:
```

### Complexity-decomposition improvements

```text
Responsibilities separated:
State ownership clarified:
Pipelines introduced:
Contracts introduced:
```

### Module-level improvements

```text
Oversized modules decomposed:
Public interfaces reduced:
Duplicated semantics removed:
Control flow simplified:
Dead abstractions removed:
```

### Verification

```text
Tests run:
Tests added:
Architectural constraints checked:
Performance checks:
```

### Remaining architectural debt

```text
Known issue:
Reason not addressed:
Priority:
Suggested future action:
```

---

# 34. Architecture Quality Scorecard

For each major subsystem assign qualitative or numerical scores for:

```text
Responsibility clarity
Ownership clarity
Dependency direction
Change locality
Interface quality
State encapsulation
Semantic uniqueness
Test isolation
Context efficiency
Repository discoverability
```

For example:

[
0=\text{very poor}
]

[
5=\text{excellent}
]

Do not optimize the numerical score itself.

Use the score to identify trends.

The important signal is:

[
Q_{\text{architecture}}(t+1)
\ge
Q_{\text{architecture}}(t)
]

as functionality grows.

---

# 35. Continuous Architecture Improvement Loop

Architecture maintenance should operate as a feedback system:

[
\text{feature development}
\rightarrow
\text{architectural pressure}
\rightarrow
\text{measurement}
\rightarrow
\text{rebuild}
\rightarrow
\text{simplified architecture}
\rightarrow
\text{feature development}
]

The rebuild is therefore not an exceptional rescue operation.

It is a normal stage of development.

---

# 36. Long-Term Objective for Agent-Coded Systems

A large codebase should not require proportionally larger reasoning contexts.

The desired scaling behavior is:

[
|\text{Repository}|\uparrow
]

while:

[
|\text{Context per local task}|
\approx
\text{constant}
]

and:

[
|\text{Relevant modules per task}|
\approx
\text{constant}
]

This is possible only when architecture continuously decomposes the software into semantically meaningful, strongly bounded regions.

The objective of periodic rebuilding is therefore to prevent:

[
\text{repository growth}
\rightarrow
\text{reasoning complexity growth}
]

and instead obtain:

[
\boxed{
\text{repository growth}
\rightarrow
\text{architectural hierarchy growth}
}
]

The distinction is fundamental.

A million-line codebase should not be treated as a million-line reasoning problem.

It should be treated as:

[
\text{system}
\rightarrow
\text{subsystem}
\rightarrow
\text{component}
\rightarrow
\text{module}
\rightarrow
\text{operation}
]

with each level eliminating irrelevant information.

---

# 37. Final Architectural Principle

The architecture should continuously answer three questions for every future coding agent:

[
\boxed{\text{Where does this requirement belong?}}
]

[
\boxed{\text{What information is actually relevant?}}
]

[
\boxed{\text{What can safely be ignored?}}
]

The third question is particularly important.

A powerful architecture does not merely help an agent find information.

**It allows the agent to prove that most information in the repository is irrelevant to the current task.**

That is the fundamental mechanism by which architectural work preserves effective agent intelligence as a software project grows.
