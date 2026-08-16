# Future Ideas Outside the Context Closure Implementation Plan

This register preserves ideas discussed during design that are intentionally
outside the committed scope of
`work/context-closure-implementation-plan.md`. They must not silently expand
the current implementation. Each idea requires a separate decision after the
core architecture index and Context Closure Compiler produce measured results.

## 1. Hybrid semantic retrieval with Qdrant

Add dense semantic retrieval and hybrid sparse/dense ranking after structural
and lexical retrieval are working.

Potential design:

```text
SCIP/CPG structural candidates   highest authority
SQLite/Recoll lexical candidates exact identifier/text authority
Qdrant semantic candidates       similarity-based supporting evidence
                    -> typed reranker
```

Semantic similarity must never override an exact compiler-resolved symbol,
normative architecture record, or specification obligation. It should answer
questions such as “where is analogous ownership handling implemented?” rather
than “where is this symbol defined?”

Adoption trigger:

- advisory measurements demonstrate recurring recall gaps that structural and
  lexical retrieval cannot solve economically;
- an embedding model, update policy, privacy policy, and cost model are chosen;
- stale vectors and source deletions can be invalidated deterministically.

## 2. Tree-sitter structural providers

Use Tree-sitter as an additional syntax provider for:

- languages without a satisfactory SCIP indexer;
- CMake, shell, Markdown, JSON, YAML, and configuration files;
- structurally meaningful chunking of incomplete or temporarily uncompilable
  source;
- fast worktree overlays between full compiler-aware index generations.

Tree-sitter should not replace SCIP for compiler-resolved C/C++ relationships.
Its facts must be labeled syntactic rather than compiler-authoritative.

## 3. Architecture interchange and an open architecture standard

Evaluate whether the harness architecture graph should import/export an
existing standard rather than remain only a private collection of TSV files.

Candidates to investigate:

- OMG Knowledge Discovery Metamodel (KDM);
- C4/Structurizr DSL for human-visible containers and components;
- ArchiMate for higher-level organizational architecture;
- SCIP for code intelligence;
- Code Property Graph conventions for implementation relationships.

The likely result is not one universal format. It may be a small harness
ontology with lossless mappings to several representations:

```text
specification obligation
architecture concept/owner
module/component
symbol/source region
typed dependency
invariant/decision/health gate
test/evidence
```

Adoption requires a round-trip test proving that normative authority,
provenance, dependency type, and source coordinates are not lost.

## 4. A typed decomposition and project-management language

Create a small declarative language that compiles into the existing
Specification IR, architecture registry, project DAG, closure request, and
validation contracts.

Possible constructs:

```text
requirement
decision
owner
invariant
deliverable
depends build|contract|integration|regression|health
acceptance
validation
context requires|permits|excludes
route luna|terra|sol
budget
```

The language would provide static checks for contradictory requirements,
cycles, missing acceptance evidence, authority inversion, unbound obligations,
and leaves that cannot compile into a closed context.

This should be considered only after the current TSV schemas stabilize. A DSL
created too early would freeze accidental complexity instead of removing it.

## 5. Fully isolated pure-function coding workers

The current plan includes a patch-only experiment. A stronger future design
would enforce the coding worker as a pure transformation:

```text
f(task, closed_context) -> patch_proposal
```

The worker would have:

```text
filesystem search: no
arbitrary file reads: no
network: no
unbounded shell: no
direct source writes: no
Git mutation: no
output: typed patch proposal only
```

The trusted harness would apply and validate the proposal. A deterministic
context service could answer narrowly typed requests such as
`MISSING_DECLARATION(symbol)` without granting general repository exploration.

This requires stronger process isolation than prompt instructions, a patch
schema, diagnostic feedback protocol, and reliable context-closure recall.

## 6. Interactive typed context expansion

Allow an isolated worker to request one exact missing dependency without
searching:

```text
CONTEXT_REQUEST
kind: TYPE_DEFINITION
symbol: rs_story_frame
reason: required by target function signature
```

The Context Closure Compiler would either return a provenance-bearing extension
or reject the request as unrelated/out of scope. Every extension would count
against the original leaf complexity budget and teach the closure quality
metrics.

This is preferable to restoring `grep` access when a closure is nearly, but not
completely, sufficient.

## 7. Structured compiler and test diagnostics

Replace text-heavy build/test transcript excerpts with normalized evidence:

```text
diagnostic kind
tool and target
file/line/symbol
primary message
causal chain
first unique failures
suppressed duplicate count
full-log hash and path
```

Potential inputs include Clang JSON/SARIF diagnostics, CTest/JUnit output,
sanitizer reports, and project-specific smoke-test records. This would reduce
token use and improve exact context expansion.

## 8. Build and validation evidence cache

Cache deterministic validation evidence by:

```text
repository revision/workspace fingerprint
build configuration
toolchain fingerprint
command/target
relevant input closure
environment contract
```

The cache could prevent managers and workers from rebuilding or rediscovering
the same known baseline. Cached evidence must be invalidated conservatively and
must never claim a pass for inputs outside its dependency closure.

## 9. Incremental and live worktree indexing

The initial implementation may rebuild compiler-aware indexes at safe
boundaries. A future indexer could support:

- changed-file lexical updates;
- changed-translation-unit SCIP updates;
- compilation-database deltas;
- generated-header dependency invalidation;
- overlays for checkpointed and uncommitted worker changes;
- a low-priority repository watch daemon.

This is useful only after full-generation correctness and index identity are
well established.

## 10. Additional language and build-system providers

Generalize repository intelligence through provider interfaces for:

- Rust, Go, Java/Kotlin, Python, JavaScript/TypeScript, and other SCIP indexers;
- CUDA/HIP-specific compiler evidence;
- Bazel, Meson, Cargo, Go modules, and language-specific test systems;
- generated bindings and cross-language FFI edges.

Each provider must declare which relationships are authoritative, inferred, or
unsupported. “No edge returned” must not be confused with “no dependency
exists.”

## 11. Specification-authorized external data indexes

Some tasks legitimately involve large datasets, generated corpora, vendored
source, or external trees such as Wikidata snapshots. Future support should use
separate index namespaces and explicit authority:

```text
dataset identity and version
approved roots
content type
retention and privacy policy
maximum indexing/search budget
whether data is implementation context or validation input
```

Repository-only defaults must remain safe, but they must not make legitimate
dataset specifications impossible.

## 12. Shared or remote content-addressed index service

For multiple machines or many worktrees, move immutable index generations to a
shared content-addressed cache. Clients would verify manifests and download
only required shards.

This requires authentication, corruption handling, privacy boundaries,
garbage collection, and compatibility negotiation. It is unnecessary for the
single-machine first version.

## 13. Automatic redesign-harness generation

The current plan can emit `REDESIGN_REQUIRED` with evidence. A future command
could turn that finding into a small architecture-redesign specification:

```text
harness-create-redesign-spec ENV_FILE REDESIGN_REPORT
```

An operator could review and launch a separate redesign harness. After its
validated branch/commit dependency is supplied, the original feature harness
could rerun specification review and decomposition.

The redesign must remain operator-approved; architecture findings must not
silently authorize broad source rewrites.

## 14. Periodic architecture-maintenance scheduling

Schedule architecture benchmark and drift analysis based on evidence such as:

- rising closure size;
- increasing module fan-out;
- repeated missing-context requests;
- ownership ambiguity;
- worsening Luna completion probability;
- recurring Terra remediation;
- architecture benchmark regressions.

The scheduler would propose maintenance, not automatically interrupt active
feature work. This extends the report-generation feedback loop in the current
plan into an operational maintenance policy.

## 15. Cross-project architecture profiles and ontology packages

Package recurring architectural concepts and proof obligations for domains such
as:

- GPU execution and device ownership;
- serialization and persistence;
- public C ABI stability;
- concurrency and transaction boundaries;
- lifecycle/state-machine correctness;
- package/replay formats.

Profiles could seed architecture indexing and decomposition without forcing Sol
to rediscover common obligations. They must remain suggestions until bound to a
project’s governing specification and actual repository facts.

## 16. Learned retrieval and closure ranking

After enough observed data exists, train or fit local ranking models using:

- context items actually read or edited;
- missing-context requests;
- accepted versus rejected patches;
- token/action cost;
- model and leaf type;
- subsystem and dependency class.

The learned ranker would optimize the order and inclusion of supporting
evidence. Hard structural dependencies and normative records remain mandatory
regardless of learned score.

## 17. Runtime evidence in the architecture graph

Enrich static relationships with bounded dynamic evidence:

- test coverage edges;
- sampled call traces;
- ownership/mutation traces;
- performance profiles;
- GPU device and synchronization traces.

Dynamic evidence can identify which of many static callers participate in a
specific behavior. It must be labeled by configuration and test scenario and
must not be treated as proof that unobserved paths are impossible.

## 18. Human architecture and context visualization

Provide graph exports and terminal/web views for:

- module and ownership graphs;
- requirement-to-symbol traceability;
- context-closure expansion and exclusion reasons;
- graph cuts proposed for further decomposition;
- architecture drift and benchmark trends.

Text-mode tree and `--why` output should remain available. A visual UI is a
usability improvement, not a dependency of decomposition correctness.

## 19. Quota-aware parallel DAG execution

Parallel execution remains deliberately disabled. It may be reconsidered only
after serial execution has stable token behavior and all of the following
exist:

- per-agent and project-wide admission control;
- global token/cost reservation;
- immediate anomaly cancellation;
- source ownership and patch conflict detection;
- dependency-safe scheduling;
- maximum concurrent Sol/Terra/Luna limits;
- deterministic recovery after partial parallel completion.

Even then, parallelism is optional. Good decomposition should make serial work
predictable and affordable; parallelism only reduces wall-clock time.

## 20. Research question: measuring removed complexity

The current plan measures predicted and observed leaf complexity. A longer-term
research direction is to measure complexity *removed* by decomposition:

```text
ambiguity resolved
architectural decisions frozen
candidate modules eliminated
dependency classes closed
independent validation boundaries created
expected strategy branching reduced
```

This could distinguish decomposition that merely creates more rows from
decomposition that genuinely lowers worker reasoning cost.

## Priority after the current plan

Suggested order, subject to measured evidence:

1. Structured diagnostics and typed context expansion.
2. Tree-sitter providers and live worktree overlays.
3. Build/validation evidence caching.
4. Architecture interchange evaluation and typed decomposition language.
5. Fully isolated pure-function workers.
6. Cross-language and external-dataset providers.
7. Automatic redesign-spec generation and periodic architecture scheduling.
8. Semantic/Qdrant retrieval only if deterministic retrieval shows a material
   recall gap.
9. Shared index services and visualization.
10. Parallel DAG execution last, if ever.

## Ideas already inside the current implementation plan

The following discussed ideas are intentionally not treated as future scope
because they are already specified in the active plan:

- SCIP and Joern repository indexing;
- SQLite/FTS5 lexical storage and optional Recoll candidates;
- reusable architecture/module/ownership maps;
- deterministic Context Closure;
- graph-aware Sol decomposition and measured Luna admission;
- architecture inconsistency detection and `REDESIGN_REQUIRED`;
- advisory-before-required rollout;
- closure provenance and explainability;
- predicted-versus-observed complexity feedback;
- architecture benchmark and rebuild reports;
- a bounded patch-only experiment;
- token, liveness, checkpoint, recovery, and serial-execution preservation.

