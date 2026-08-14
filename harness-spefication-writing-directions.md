# Directions for writing specifications for the complexity-decomposition harness

## 1. Purpose

Use these directions when preparing a coding specification for the filesystem
harness. The harness accepts one `SPECIFICATION` file for one project. It does
not consume a fan-out manifest and it does not require the specification author
to launch or coordinate a collection of independent worker agents.

The specification is the product and acceptance authority. The harness's fresh
decomposition planner reads it, derives a dependency DAG, registers architecture
guards when enabled, and then lets one manager/worker workflow advance through
dependency-ready leaves. An optional Oracle audits the completed plan against
the original specification and every document that the master specification
marks as a mandatory normative reference.

## 2. Required harness mental model

Write for this lifecycle:

```text
one master SPECIFICATION
  -> fresh decomposition planner and critic
  -> immutable, topologically ordered project DAG
  -> manager publishes one dependency-ready leaf
  -> worker implements that bounded leaf
  -> manager independently reviews, checkpoints, or rejects it
  -> manager publishes the next dependency-ready leaf
  -> final integration leaves
  -> independent Oracle audit
```

The DAG may contain logically independent branches, but the ordinary harness
uses one worker route and advances one published leaf at a time. Do not describe
independent branches as concurrently running agents, repositories, worktrees,
or merge lanes.

## 3. Single master specification

Provide exactly one master file as the environment's `SPECIFICATION` value.
The master file must:

1. state the complete project outcome and completion boundary;
2. follow the repository's specification-definition guide;
3. link the applicable development policy with a repository-relative link;
4. identify the accepted baseline revision and observable baseline state;
5. declare every mandatory referenced document by repository-relative path;
6. state that the decomposition planner, manager, affected worker leaves, and
   Oracle must read the mandatory references relevant to their decisions;
7. define precedence between the master and referenced documents;
8. expose enough dependency, ownership, contract, and validation information
   for the planner to derive a correct DAG; and
9. define final integrated acceptance independently of any manager-created plan.

Referenced lane documents are allowed. They are normative annexes, not separate
harness inputs. The master remains the coordination and completion authority.
When the master and an annex conflict, the master must define whether it
overrides the annex or whether the conflict is a specification blocker. Never
leave precedence implicit.

Recommended precedence:

```text
master project boundary and cross-lane dependency rules
  > lane-local scope and integration rules
  > requirement-specific behavior in the applicable normative annex
  > informative reports and historical documents
```

The master must not merely list annex filenames. It must summarize their
deliverables, dependency edges, owned surfaces, focused evidence, and the final
integration obligation so the decomposition planner can construct the DAG even
before opening a particular annex. It must explicitly require the planner and
Oracle to read all normative annexes completely.

## 4. Specification format

Follow `design/specification-definition-guide.md`. A full specification uses
the guide's ordered 34-section structure. Each normative requirement has one
stable ID and one independently testable obligation. Include the exact
machine-readable registry fields required by the guide. Each named test must
contain the guide's complete test record, including explicit `Test ID`, `Title`,
`Fixture`, `Input`, `Execution procedure`, and `Cleanup procedure` fields.

Use only repository-relative paths in specifications and referenced commands.
Use build directories outside the source tree but express them relative to the
repository, for example `../build/project-lane`.

Do not hide mandatory behavior in unidentified prose. If a sentence is required
for acceptance, give it a requirement ID and include it in the registry and
traceability matrices.

## 5. Requirements that produce a useful DAG

The specification must expose dependencies without prescribing manager task
IDs. Describe dependencies in terms of accepted artifacts and observable
contracts, for example:

- Query execution consumes the accepted Semantic IR contract and therefore
  cannot reach integration acceptance before Semantic IR acceptance.
- CEGIS consumes the accepted finite program-domain representation and cannot
  reach integration acceptance before Program Domain acceptance.
- Final Computing acceptance depends on every named Wave stage.

Distinguish these relationships:

- `depends on`: the consumer cannot be correctly implemented or accepted until
  the producer contract or artifact is accepted;
- `may be developed independently`: no producer artifact is required, although
  the single worker means the harness still executes one leaf at a time;
- `integration dependency only`: local implementation can be validated with a
  typed fixture, but final acceptance must consume the real accepted producer;
- `regression boundary`: behavior that must remain unchanged but does not
  produce a new artifact for the consumer; and
- `final health dependency`: a cumulative gate rerun after several components.

For each major component, provide:

- one independently useful deliverable;
- precise producer and consumer contracts;
- exact public or internal symbols where known;
- bounded source path groups;
- deterministic focused validation;
- required evidence;
- explicit prerequisites; and
- the integration milestone that consumes it.

Do not hand-author the harness TSV DAG inside the product specification unless
the product itself requires an immutable execution sequence. The decomposition
planner owns task granularity, parent IDs, leaf classifications, and worker
routing. The specification supplies the facts needed to derive them.

## 6. Lane and component scope

An allowlist in a component annex is task-local, not globally frozen for the
entire project. Use language such as:

> For DAG leaves whose deliverable is attributed to this component, ordinary
> worker edits are limited to the following paths. Files owned by other
> components are read-only dependencies for those leaves. This restriction does
> not prohibit a later dependency-approved leaf from editing its own declared
> component paths.

Separate three scopes:

1. component-owned implementation paths;
2. shared integration paths that only an explicit integration leaf may edit;
3. globally frozen paths that no Wave leaf may edit.

Never say that every other lane is frozen without qualifying the statement as a
component-leaf boundary. Otherwise multiple normative annexes freeze one
another and the planner cannot derive a coherent whole-project plan.

Avoid path overlap between unrelated component leaves. When a shared path is
unavoidable, identify one owner or an explicit integration leaf and define the
consumer dependency. Evidence reports must be lane-specific so sequential
checkpoints do not overwrite one another.

File ownership is a planning boundary, not a human blocker. If a necessary
repository-local prerequisite falls outside an ordinary worker leaf, the
manager can create bounded baseline remediation under the harness protocol.

## 7. Task size and routing affordances

The decomposition planner will split the project. Help it create good leaves:

- keep one cohesive implementation concern per potential leaf;
- name exact symbols and bounded file groups;
- separate contract or concurrency decisions from routine implementation;
- make routine implementation and focused tests independently verifiable;
- avoid a single acceptance criterion that necessarily changes many unrelated
  components; and
- provide the smallest deterministic validation that proves each increment.

Do not label work for Luna or Terra in the specification unless model routing is
a product requirement. The harness decides routing. Design requirements,
cross-component contracts, concurrency protocols, ambiguous behavior, and
unexplained integration failures naturally require decision-oriented leaves;
bounded implementation, mechanical propagation, focused fixes, tests, and
documentation can become low-complexity leaves after those decisions exist.

## 8. Architecture information

When architecture guards are enabled, the planner constructs invariants,
decisions, edge contracts, node bindings, health gates, and debt records. The
specification must supply truthful source material for that registry:

- explicit global invariants with stable requirement IDs;
- decisions already fixed by the specification;
- unresolved alternatives that genuinely require a design decision;
- producer/consumer API, representation, ownership, serialization, error, and
  concurrency contracts;
- focused compatibility checks for each contract edge;
- milestone and final health checks; and
- declared accepted debt, if any, with consequence and remediation ownership.

Do not invent architecture sidecar IDs in the specification. Do not require the
worker to create harness architecture state. The planner and manager own those
transactions.

## 9. Focused validation and aggregate evidence

Every implementation leaf must have a focused validation that is attributable
to its owned behavior. Prefer an existing focused selector, unit executable,
component smoke, compile target, or inspection command.

A broad selector such as `--computing-all` is not a focused leaf gate. It may be
used as baseline or integration evidence only when its unrelated nonzero exit is
explicitly tolerated and the command separately asserts the owned row. For
example:

```sh
set +e
output="$(../build/wave-c/resys_semantic_smoke --computing-all 2>&1)"
status=$?
set -e
test "$status" -eq 1
printf '%s\n' "$output" | grep -F 'stage=semantic-ir status=PASS'
```

In a one-line registered validation, preserve both `status=$?` and
`test "$status"` so the harness recognizes that the unrelated aggregate failure
is tolerated. Do not set `HARNESS_BROAD_GATE_REQUIRED=1` unless the human-owned
specification truly requires whole-project aggregate success.

For a component that lacks a focused selector, use its existing focused API or
test surface for leaf acceptance. Reserve tolerated aggregate row checking for
the component's integration milestone. If neither exists and adding one is
required, assign ownership of that test surface to an explicit test or
integration requirement rather than silently editing a globally frozen file.

Final project acceptance may combine focused gates and one tolerated aggregate
gate. The final expected aggregate must name its exact status, stage rows,
credited requirement count, deferred stages, and expected exit status.

## 10. GPU requirements

When GPU execution is required, specify native meaning-bearing parallel work,
not merely device memory copies or an empty kernel. Define and test:

- selected physical-device identity;
- nonempty disjoint primary work on each selected GPU when the fixture has
  enough work;
- enqueue of independent device work before cross-device collection;
- nondefault streams and completion events where required;
- device-side semantic evaluation;
- deterministic owner routing and canonical merge;
- one-, two-, and reversed-device topology parity;
- zero CPU semantic fallback;
- typed failure for unavailable required devices and HIP failures;
- checked cleanup with no partial semantic publication; and
- compact evidence containing work, launch, owner, merge, failure, cleanup, and
  fallback fields.

Host code may validate inputs, allocate resources, launch work, synchronize at
declared boundaries, transport bytes, and serialize results. It must not perform
the meaning-bearing computation that the specification assigns to the GPU.

## 11. Integration milestones

Define integration milestones by accepted behavior, not by branch merges. A
typical project contains:

1. contract and representation decisions;
2. bounded component implementations;
3. component-focused tests;
4. producer/consumer compatibility checks;
5. component stage promotion;
6. cumulative subsystem health gates; and
7. final project acceptance.

An integration milestone may edit only explicitly identified shared integration
surfaces. If shared surfaces are already wired and frozen, the milestone should
verify them without edits.

Typed local fixtures are acceptable for isolated implementation only when the
specification says so. A fixture is not a substitute for the real producer at
final integration. State the exact milestone at which the consumer must use the
accepted producer artifact.

## 12. Evidence, commits, and reports

The harness preserves commits, checkpoints, results, reviews, and architecture
evidence. The product specification should require durable behavioral evidence,
not separate-agent merge instructions.

For each component, name:

- focused build and test output;
- exact statuses and hashes;
- changed-path and symbol inventory;
- compatibility or migration evidence;
- GPU topology and cleanup evidence when applicable; and
- a component-specific implementation report only when a repository report is
  actually required.

Do not require workers to run raw Git history mutations. The harness owns source
commit transactions. Do not describe manual merging of worker repositories.

## 13. Oracle traceability

The master specification must require the final Oracle to verify:

- every master requirement;
- every requirement in every mandatory normative annex;
- every accepted DAG item and manager review;
- all architecture invariants, decisions, edges, health gates, and debt;
- focused component acceptance;
- cumulative integration acceptance;
- changed-path ownership; and
- the final completion boundary.

Every original requirement ID must map to reproducible evidence or an explicit
finding. Informative handoffs and historical reports must not silently become
acceptance authorities.

## 14. Anti-patterns

Do not write:

- "launch one worker per lane";
- "all workers run concurrently";
- "merge the six worker branches in this order";
- "each lane receives its own harness specification" for one project;
- globally contradictory per-lane freezes;
- a local fixture as permanent cross-component integration evidence;
- raw `--*-all` as a mandatory successful focused gate;
- acceptance that depends on unrelated known failures disappearing;
- absolute source or build paths;
- open-ended edit exceptions; or
- requirements that make repository-local implementation difficulty a human
  product decision.

## 15. Preflight checklist for a specification writer

Before handing the master specification to the harness, verify:

- [ ] There is exactly one intended `SPECIFICATION` input.
- [ ] Every mandatory annex is referenced with a repository-relative path.
- [ ] The master requires planner, manager, relevant workers, and Oracle to read
      the applicable normative references.
- [ ] Master/annex precedence is explicit.
- [ ] The document follows the full specification-definition guide.
- [ ] Requirement and test registries pass strict duplicate-key validation.
- [ ] Dependencies are artifact/contract dependencies, not agent launch order.
- [ ] Component allowlists are explicitly leaf-local.
- [ ] Shared integration paths have one owner.
- [ ] Globally frozen paths are unambiguous.
- [ ] Potential routine coding leaves have bounded paths, named symbols, and
      deterministic focused validation.
- [ ] Broad aggregate commands tolerate unrelated failure and assert exact owned
      results separately.
- [ ] Native GPU work and zero semantic fallback are explicitly testable.
- [ ] Typed fixtures are replaced by real producer artifacts at integration.
- [ ] Final acceptance names exact focused gates, aggregate rows/count, deferred
      scope, expected exit, and evidence.
- [ ] Oracle traceability includes every mandatory referenced requirement.
- [ ] No instruction assumes parallel agents, separate worktrees, or manual
      branch merging.

## 16. Wave-oriented master specification pattern

For a multi-component wave, the master should contain a compact table like:

| Component | Normative annex | Produces | Consumes | Leaf-local owned paths | Focused evidence | Integration dependency |
|---|---|---|---|---|---|---|
| A | relative annex path | typed artifact A | accepted baseline | bounded A paths | focused A selector | final integration |
| B | relative annex path | typed artifact B | accepted A contract | bounded B paths | focused B selector | A then final integration |

Follow it with explicit milestone requirements, for example:

- `INT-WAVE-001`: Component A integration acceptance requires its focused tests
  and exact aggregate row, while unrelated aggregate failure is tolerated.
- `INT-WAVE-002`: Component B final integration consumes the accepted Component
  A artifact rather than a local substitute.
- `INT-WAVE-003`: Final wave acceptance requires every component row, exact
  aggregate credit, unchanged deferred-stage status, and all cumulative health
  gates.

These are product dependencies from which the harness derives its DAG. They are
not manager task IDs and do not prescribe how many worker turns the harness will
use.
