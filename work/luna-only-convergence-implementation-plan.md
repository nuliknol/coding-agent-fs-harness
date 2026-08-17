# Luna-Only Convergence Engine

Status: implementation plan

Created: 2026-08-17

## 1. Objective

Compile every internally consistent, locally implementable specification into a
sequence of independently verifiable implementation transactions that can be
completed by Luna-class models without Sol or Terra fallback.

The supported boundary is deliberate. If the governing specification requires
incompatible observable outcomes, or completion needs unavailable human
authority, a secret, or an external manual state transition, the harness must
emit a structured clarification or dependency request. It must not spend model
turns attempting to implement an impossible or externally blocked outcome.

The central architectural change is to replace the present binary Context
Closure launch gate and model-escalation loop with a Luna-only convergence
engine:

```text
specification
  -> typed obligation and acceptance graph
  -> deterministic recursive decomposition
  -> repairable Context Closure
  -> Luna patch proposal
  -> trusted validation
       pass                 -> checkpoint or accept
       missing evidence     -> typed context expansion -> Luna repair
       broad boundary       -> deterministic child-DAG graft -> Luna children
       local prerequisite   -> prerequisite child -> resume parent
       incompatible outcome -> CLARIFICATION_REQUEST
```

No implementation, repair, review, decomposition, architecture, or audit branch
may silently route to Sol or Terra when Luna-only policy is enabled.

## 2. Why the current implementation does not meet the objective

Context Closure currently prevents an under-specified Luna launch, but a
non-ready closure becomes a synthetic `NEEDS_DECOMPOSITION` worker result. The
manager then owns repair or replanning, manager remediation is forced to Terra,
and exhausted Luna strategies are normalized to Terra. The closure compiler
also labels oversized suggested cuts `DECOMPOSE_OR_TERRA`.

Consequently, Context Closure is an admission/safety gate rather than a
completion mechanism. It can save one unsuitable Luna invocation while causing
more expensive planning and remediation inference. That is not an acceptable
token or convergence result.

The external repository tools are useful foundations, not the missing control
plane. SCIP and Joern can provide symbol, ownership, call, and data-flow facts,
but the harness still needs deterministic state transitions that consume those
facts and make measurable progress.

## 3. Required invariants

### 3.1 Model policy

Introduce a machine-enforced policy:

```text
HARNESS_MODEL_POLICY=legacy|luna_only
HARNESS_ESCALATION_POLICY=legacy|decompose
```

Under `luna_only`:

- every inference role must use `LUNA_WORKER_MODEL`;
- model fallback must remain within the same permitted Luna model;
- attempted Sol/Terra invocation is a policy error with a durable event;
- task routing cannot contain a Terra execution route;
- Luna exhaustion transitions to smaller decomposition, context repair, or an
  external dependency classification, never a stronger model.

The policy must cover specification review, architecture fit, DAG construction
and repair, architecture binding, manager planning/review/remediation, coding,
and final audit. Enforcing only the worker route would leave the expensive loop
intact.

### 3.2 Semantic conservation

Decomposition maximizes useful complexity reduction, not row count. Every split
must conserve typed obligation facets:

```text
parent facets = union(child facets)
```

Each executable child must have:

- one observable behavior or proof outcome;
- one bounded mutation/inspection seam;
- one focused validation oracle;
- resolved prerequisite contracts;
- a Context Closure within Luna limits.

The normalized IR must assign stable facet identifiers for behavior, failure,
state, ownership, concurrency, artifact, compatibility, and validation. The DAG
validator must reject lost facets, duplicated exclusive facets, and children
that have no independent acceptance evidence.

### 3.3 Durable progress

A root Goal ID survives context repair, child-DAG grafting, harness deployment,
and process recovery. Accepted criteria, commits, diagnostics, and closure
extensions remain durable. Planning failures must not require project-wide
restart or loss of already accepted work.

Progress is measured by decreasing unresolved obligation facets, decreasing
unique validation failures, decreasing closure excess, or newly verified
evidence. Repeating the same state is a bug/circuit-breaker condition, not a
reason to invoke a stronger model.

### 3.4 Investigation fuses are immutable fail-stop boundaries

Luna convergence must reduce usage before a fuse is reached; it must never
reinterpret a fuse as an automatic retry allowance. The following defaults
remain independent, hard investigation boundaries:

- 500,000 authoritative processed tokens per agent invocation;
- 500,000 live-estimated processed tokens per agent invocation;
- 500,000 cumulative processed tokens per worker task;
- the configured role-specific action, command-output, root review/replan,
  root lifetime, and root processed-token limits.

Crossing one of these boundaries publishes its durable anomaly or architecture
reassessment record and suppresses further affected launches until an operator
investigates and explicitly resolves it. Model policy cannot bypass that
interlock. A verified criterion, ordinary checkpoint, retry, restart, or
context refresh cannot reset monotonic fuse accounting. The only authorized
epoch is the recorded one-time migration from an already exhausted legacy
broad boundary to mandatory append-only Luna child criteria; its original
counters remain preserved as the baseline.

## 4. Repairable Context Closure

`INCOMPLETE` and `NEEDS_FURTHER_DECOMPOSITION` become internal compiler states,
not synthetic worker outcomes. Closure preparation must emit a typed condition
and a deterministic next action.

| Condition | Deterministic transition |
| --- | --- |
| missing indexed symbol | refresh affected unit or query another provider |
| dirty/checkpointed worktree | refresh the live overlay |
| source/token budget exceeded | split at a symbol, ownership, or test seam |
| dependency fanout exceeded | graft prerequisite children |
| missing test/build ownership | compile build/test ownership evidence |
| provider unsupported | bounded Tree-sitter/lexical fallback |
| incompatible normative outcomes | `CLARIFICATION_REQUEST` |

The closure manifest needs separate fields for condition, evidence class,
repair action, implicated provider, affected paths/symbols, budget delta, and
whether semantic decomposition is required. A generic `CONTEXT_INCOMPLETE`
label is insufficient.

## 5. Recursive child-DAG grafting

Rejected roots acquire durable children rather than being rewritten as another
version of the same leaf. The graph compiler should prefer, in order:

1. an independently testable behavior boundary;
2. a producer/consumer contract boundary;
3. an ownership or representation boundary;
4. a build target or test fixture boundary;
5. an API-compatible migration stage.

Large cross-component changes are expressed through compatibility-preserving
stages: introduce a contract, add an adapter, implement producers, implement
consumers, switch integration, remove scaffolding, then run global validation.
Global validation is a deterministic validation node, not a Terra coding leaf.

The cut compiler must return concrete child rows with facet allocation,
dependencies, allowed paths, required symbols, acceptance evidence, focused
validation, and estimated closure cost. A bounded Luna microplanner may select
among compiler-valid candidates, but may not invent unvalidated authority or
route to another model.

## 6. Live repository overlays and tool cost

Use an immutable baseline index plus a workspace overlay:

- changed-file Tree-sitter/lexical facts;
- changed-translation-unit SCIP facts;
- compilation database and build graph deltas;
- generated-header invalidation;
- checkpointed and uncommitted workspace fingerprints;
- overlay records that shadow baseline facts.

Joern must be lazy and digest-cached. Run it only for a named data-flow,
mutation, or ownership question whose answer is not already available. Never
perform a full-project Joern rebuild for every leaf. Index refresh should be
coalesced and resource-limited.

## 7. Typed diagnostic feedback and context expansion

The trusted harness runs validation and converts compiler, test, sanitizer, and
build output into compact diagnostics:

```text
diagnostic kind
tool and target
file, line, and symbol
primary message
causal chain
first unique failures
suppressed duplicate count
full-log digest and retained path
```

The next Luna proposal receives the original closure plus only the diagnostic
delta. A patch-only Luna may request narrowly typed evidence:

```text
TYPE_DEFINITION(symbol)
CALLER_CONTRACT(symbol)
FAILING_ASSERTION(test)
BUILD_OWNER(path)
REPRESENTATION_WRITER(symbol)
```

The context service validates relevance and authority, supplies a
provenance-bearing excerpt, charges it to the original leaf budget, or rejects
it. General repository exploration stays disabled.

## 8. Trusted transaction runner

Move non-semantic work out of model prompts. The harness owns:

- patch parsing, scope checking, and application;
- workspace and baseline fingerprints;
- compilation and focused tests;
- diagnostic normalization;
- obligation evidence accounting;
- checkpoint/commit transactions;
- dependency scheduling;
- architecture-impact extraction where deterministic;
- cache validation and invalidation.

Luna receives a leaf-type-specific compact contract and proposes code or a
typed context request. It does not manage Git, search the repository, parse
large raw logs, or reproduce harness transaction protocols.

Validation evidence is cached by repository/workspace fingerprint, toolchain,
environment contract, command/target, and relevant input closure. A cached pass
may only be reused when the complete dependency closure is unchanged.

## 9. Luna-only role design

All semantic roles use bounded Luna calls over compiled evidence:

- specification normalizer: produces typed obligations and conflicts;
- architecture critic: checks compiled contracts and invariants;
- microplanner: selects among valid decompositions;
- implementer: maps leaf closure and diagnostic delta to a patch;
- patch critic: checks the bounded diff against assigned obligations;
- audit critic: checks obligation/evidence coverage.

For high-risk semantic choices, use independent Luna passes and deterministic
agreement/consistency rules rather than a stronger model. If the governing
specification does not decide between incompatible observable alternatives,
emit clarification instead of guessing.

## 10. In-place migration

At a safe scheduler boundary:

- map non-ready leaves to `CLOSURE_REPAIR`;
- map planning-stalled roots to deterministic graph compilation;
- map manager-remediation tasks to typed local-prerequisite children;
- preserve accepted specifications, installed DAG authority, Goal IDs,
  criterion ledgers, commits, and verified checkpoints;
- record the old and new state in the event journal;
- resume from the first unresolved facet without a project-wide replan.

## 11. Implementation sequence

### Phase A — policy and state safety

- add and validate model/escalation policy settings;
- centralize role-to-model resolution;
- prohibit non-Luna inference under Luna-only policy;
- prohibit Terra routes and escalation normalization;
- add compatibility-preserving event fields and tests.

### Phase B — typed closure repair

- define closure condition/action schema;
- classify current unresolved and budget reasons;
- dispatch provider refresh, overlay refresh, graph split, prerequisite graft, or
  clarification without manufacturing a worker result;
- add idempotence and no-repeat guards.

### Phase C — live overlay index

- introduce baseline-plus-overlay identity;
- update changed files and translation units;
- make closure queries overlay-aware;
- make Joern lazy, cached, and resource-governed.

### Phase D — recursive decomposition compiler

- introduce typed obligation facets;
- implement facet-conserving child-DAG grafts;
- synthesize compatibility migration stages;
- preserve root progress and resume semantics.

### Phase E — diagnostic repair loop

- normalize compiler/test evidence;
- implement typed context requests;
- add bounded Luna repair turns and strict progress measures;
- cache focused validation evidence.

### Phase F — compact Luna roles and migration

- generate leaf-specific prompts;
- move transaction mechanics to the trusted runner;
- migrate active project state at safe boundaries;
- remove remaining required Sol/Terra control-flow assumptions.

## 12. Completion and promotion criteria

The refactor is not complete until production evidence demonstrates:

- zero Sol/Terra inference calls under `luna_only`;
- at least 95% closure readiness after automatic repair;
- less than 2% false closure blocks;
- at least 85% first-pass verified Luna completion;
- at least 98% verified completion within three typed diagnostic rounds;
- zero unchanged-leaf retry loops;
- zero project restarts required for context/decomposition failures;
- lower total tokens per verified obligation, including planning and review;
- lower divergence/defect escape than the pre-closure baseline;
- every non-completion ends in a precise external dependency or structured
  clarification request.

Route share alone is not success. The primary metric is total cost and verified
completion per obligation with no defect-rate regression.

## 13. Non-goals and sequencing cautions

- Do not raise context limits to conceal poor decomposition.
- Do not add semantic/vector retrieval before deterministic recall gaps are
  measured.
- Do not add parallel execution before state, overlay, merge ownership, and
  validation semantics are reliable.
- Do not treat more DAG rows as progress unless each row reduces measured
  reasoning cost and has an independent proof boundary.
- Do not rebuild global Joern/SCIP state when a bounded overlay refresh answers
  the question.
