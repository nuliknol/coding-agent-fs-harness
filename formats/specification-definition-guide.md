# Specification Authoring Directive: Atomicity, Traceability, and Verifiability

## 1. Objective

Create a complete implementation specification that is:

* maximally atomic;
* mechanically traceable;
* independently auditable;
* deterministically testable;
* resistant to ambiguous interpretation;
* suitable for implementation by a coding agent;
* suitable for later compliance auditing by a separate agent.

The specification must function as a finite collection of verifiable obligations, not merely as a narrative description of the desired system.

The final implementation must be auditable through the chain:

[
\text{Goal}
\rightarrow
\text{Requirement}
\rightarrow
\text{Design element}
\rightarrow
\text{Implementation symbol}
\rightarrow
\text{Test}
\rightarrow
\text{Evidence}
]

Every mandatory statement must participate in this traceability chain.

---

# 2. Fundamental authoring rules

## 2.1 Use normative language consistently

Use the following words with precise meanings:

* **MUST**: mandatory for specification compliance.
* **MUST NOT**: prohibited.
* **SHALL**: equivalent to MUST, but prefer MUST for consistency.
* **SHOULD**: recommended but not required for compliance.
* **MAY**: optional.
* **INFORMATIVE**: explanatory text that creates no implementation obligation.

Do not use ambiguous obligation words such as:

* should ideally;
* preferably;
* generally;
* normally;
* where appropriate;
* as needed;
* robust;
* efficient;
* scalable;
* flexible;
* complete;
* production-ready;
* user-friendly.

Such terms may be used only when they are followed by explicit measurable definitions.

Bad:

> The system must be efficient.

Good:

> `PERF-EXEC-001`: The system MUST process at least 1,000,000 facts per second under benchmark configuration `BENCH-CONFIG-001`.

---

# 3. Requirement identity

## 3.1 Assign every requirement a permanent identifier

Every mandatory requirement MUST have a globally unique, stable identifier.

Use this format:

```text
<CATEGORY>-<SUBSYSTEM>-<NUMBER>
```

Examples:

```text
ARCH-SHARD-001
FUNC-DELTA-001
DATA-FACT-003
DET-EXEC-002
ERR-PARSE-004
TEST-JOIN-007
PERF-GPU-003
DOC-API-002
SEC-INPUT-001
```

Identifiers MUST remain stable across specification revisions.

If a requirement is deleted, its identifier MUST be retired and MUST NOT be reused.

If a requirement changes semantically, record the change in the revision history.

---

## 3.2 Use requirement categories

At minimum, classify requirements into the following categories:

```text
GOAL		High-level system outcomes
ARCH		Architecture and component boundaries
FUNC		Externally observable behavior
DATA		Data structures, schemas, ownership, and lifetime
ALG		Algorithms and formal operators
DET		Determinism and reproducibility
STATE		State transitions and lifecycle
INT		Component integration
API		Public and internal interfaces
ERR		Error detection and handling
PERF		Performance and resource limits
CONC		Concurrency and synchronization
SEC		Security and input validation
TEST		Required tests and validation procedures
OBS		Logging, metrics, tracing, and diagnostics
DOC		Documentation requirements
BUILD		Build and packaging requirements
PORT		Platform and portability requirements
EXT		Extension mechanisms
MIG		Migration and compatibility requirements
```

A requirement MUST belong to exactly one primary category, but it MAY reference related requirements in other categories.

---

# 4. Atomicity rules

## 4.1 One independently verifiable obligation per requirement

Each requirement MUST describe exactly one obligation that can independently pass or fail.

A requirement is not atomic if it contains multiple obligations joined by words such as:

* and;
* or;
* as well as;
* while also;
* including;
* together with.

Bad:

```text
The system MUST shard facts across GPUs, eliminate duplicates, preserve
determinism, and report communication failures.
```

Required decomposition:

```text
ARCH-SHARD-001:
Every persistent fact MUST have exactly one owning GPU.

ALG-UNIQUE-001:
Duplicate candidate facts MUST be removed before delta insertion.

DET-SHARD-001:
Fact ownership MUST be identical across executions with identical inputs,
configuration, executable, and GPU count.

ERR-COMM-001:
A failed inter-GPU transfer MUST produce error code ERR_GPU_TRANSFER.
```

---

## 4.2 Split requirements by observable outcome

Two behaviors belong in separate requirements when they can fail independently.

For example, separate:

* allocation from deallocation;
* parsing from validation;
* validation from execution;
* execution from logging;
* success behavior from error behavior;
* single-GPU behavior from multi-GPU behavior;
* functional correctness from performance;
* serialization from deserialization;
* storage from retrieval;
* local joins from distributed joins.

---

## 4.3 Do not hide requirements in explanatory prose

Any sentence containing MUST or MUST NOT is a normative requirement and MUST have an identifier.

No mandatory obligation may appear only in:

* introductions;
* examples;
* diagrams;
* notes;
* rationale sections;
* tables without identifiers;
* appendices;
* test descriptions;
* architectural explanations.

If a diagram implies a mandatory connection or behavior, create a corresponding identified requirement.

---

## 4.4 Do not use examples as substitutes for requirements

Examples are informative unless explicitly linked to normative requirements.

Bad:

> For example, the system could use a 128-bit hash to distribute facts.

Good:

```text
ALG-HASH-001:
The ownership function MUST use the 128-bit hash algorithm defined in
ALGORITHM-HASH128-001.
```

The example may then illustrate the requirement, but it does not define it.

---

# 5. Required structure for every requirement

Each requirement entry MUST contain the following fields.

```text
Requirement ID:
Title:
Category:
Normative statement:
Rationale:
Source:
Parent goal:
Dependencies:
Related requirements:
Preconditions:
Inputs:
Outputs:
State changes:
Failure behavior:
Acceptance criterion:
Verification method:
Required test IDs:
Required evidence:
Priority:
Applicability:
Status:
```

## 5.1 Field definitions

### Requirement ID

Permanent unique identifier.

### Title

Short descriptive name.

### Category

Exactly one primary requirement category.

### Normative statement

One atomic MUST or MUST NOT statement.

### Rationale

Why the requirement exists.

Rationale is informative and MUST NOT introduce new obligations.

### Source

The origin of the requirement, such as:

* user request;
* architectural decision;
* external standard;
* safety constraint;
* derived dependency;
* compatibility requirement.

### Parent goal

The higher-level goal this requirement satisfies.

Every non-goal requirement MUST trace to at least one goal.

### Dependencies

Requirement IDs that must be satisfied before this requirement can operate correctly.

Dependencies MUST be directional.

### Related requirements

Non-dependent but relevant requirement IDs.

### Preconditions

Conditions that must be true before the behavior is invoked.

### Inputs

Explicitly defined inputs, types, valid ranges, ownership, and mutability.

### Outputs

Explicitly defined outputs, types, ownership, and valid states.

### State changes

Exact persistent or temporary state mutations caused by the behavior.

Use “none” for pure operations.

### Failure behavior

Exact behavior for invalid input, resource exhaustion, dependency failure, or internal failure.

### Acceptance criterion

A finite binary condition that determines PASS or FAIL.

### Verification method

One or more of:

```text
INSPECTION
STATIC_ANALYSIS
UNIT_TEST
INTEGRATION_TEST
SYSTEM_TEST
PROPERTY_TEST
MODEL_CHECK
FORMAL_PROOF
BENCHMARK
MANUAL_REVIEW
```

### Required test IDs

Tests that demonstrate compliance.

### Required evidence

Artifacts the implementation must produce, such as:

* test output;
* source symbol;
* log record;
* output hash;
* benchmark report;
* proof artifact;
* generated schema;
* trace file.

### Priority

Use:

```text
CRITICAL
HIGH
MEDIUM
LOW
```

Priority MUST NOT change whether a mandatory requirement is required for compliance.

### Applicability

Use:

```text
ALWAYS
CONDITIONAL
PLATFORM_SPECIFIC
FUTURE_PHASE
```

Conditional requirements MUST state the exact enabling condition.

### Status

During specification authoring, use:

```text
DRAFT
APPROVED
DEFERRED
REJECTED
```

Implementation status does not belong in the specification source of truth.

---

# 6. Acceptance criteria

## 6.1 Every mandatory requirement needs a binary acceptance criterion

The criterion must permit exactly one of the following results:

```text
PASS
FAIL
NOT_APPLICABLE
BLOCKED
```

Do not use subjective states such as:

```text
mostly passed
largely complete
approximately correct
sufficiently implemented
appears functional
```

If a requirement can be partially satisfied, it is not atomic enough and MUST be decomposed.

---

## 6.2 Acceptance criteria must identify the observable evidence

Bad:

> Pass when deterministic behavior is confirmed.

Good:

```text
Acceptance criterion:

1. Execute test TEST-DET-004 100 times.
2. Use identical input bytes, executable hash, configuration, GPU count,
   and initial persistent state.
3. Capture the ordered output fact stream from every execution.
4. Calculate a SHA-256 digest of each output stream.
5. PASS only if all 100 digests are identical.
```

---

## 6.3 Define test conditions completely

Each acceptance criterion must define all material conditions, including:

* hardware configuration;
* GPU count;
* operating system;
* compiler;
* build mode;
* input dataset;
* initial state;
* environment variables;
* number of iterations;
* timeout;
* expected result;
* numerical tolerance;
* failure code;
* output ordering;
* resource limits.

Do not leave unspecified variables that could change the result.

---

## 6.4 Define numerical tolerances explicitly

Never use “approximately equal” without a tolerance rule.

Specify one of:

[
|x-y| \leq \epsilon
]

[
\frac{|x-y|}{\max(|x|, |y|)} \leq \epsilon
]

or exact bitwise equality.

State:

* absolute tolerance;
* relative tolerance;
* units;
* rounding mode;
* overflow behavior;
* NaN behavior;
* infinity behavior.

For deterministic integer and symbolic operations, prefer exact equality.

---

# 7. Traceability requirements

## 7.1 Goal-to-requirement traceability

Every requirement MUST trace to at least one approved goal.

No orphan requirement is permitted.

Every goal MUST be supported by at least one lower-level requirement.

---

## 7.2 Requirement-to-design traceability

Every requirement MUST identify the intended design component responsible for satisfying it.

Use component identifiers such as:

```text
COMP-PARSER
COMP-SHARD-MANAGER
COMP-JOIN-ENGINE
COMP-DELTA-ENGINE
COMP-GPU-TRANSPORT
COMP-PROVENANCE-STORE
```

This linkage does not prescribe filenames unless filenames are explicitly part of the architecture.

---

## 7.3 Requirement-to-test traceability

Every mandatory requirement MUST link to at least one verification artifact.

Every test MUST link back to one or more requirements.

No unlinked test and no untested mandatory requirement are permitted unless the verification method is formal proof, inspection, or another explicitly approved method.

---

## 7.4 Bidirectional traceability

Produce the following mappings:

```text
Goal → Requirements
Requirement → Parent goals
Requirement → Components
Component → Requirements
Requirement → Tests
Test → Requirements
Requirement → Evidence
Evidence → Requirements
Requirement → Dependencies
Requirement → Derived requirements
```

Traceability must be navigable in both directions.

---

# 8. Requirement derivation

## 8.1 Mark derived requirements explicitly

When one requirement logically implies another implementation obligation, create a separate derived requirement.

Example:

```text
DET-EXEC-001:
Identical executions MUST produce identical ordered output facts.
```

This may derive:

```text
DET-ORDER-001:
The system MUST define a deterministic global ordering for output facts.

DET-HASH-001:
Hash table iteration order MUST NOT affect observable output order.

DET-REDUCE-001:
Parallel reductions MUST use a deterministic reduction order.
```

Each derived requirement MUST identify its source requirements.

---

## 8.2 Do not leave necessary implications implicit

For each requirement, ask:

* What data structure is necessary?
* What API is necessary?
* What error handling is necessary?
* What state transition is necessary?
* What concurrency rule is necessary?
* What test is necessary?
* What diagnostic evidence is necessary?
* What cleanup behavior is necessary?
* What happens at minimum and maximum limits?
* What happens with zero elements?
* What happens with duplicate elements?
* What happens with malformed input?
* What happens after partial failure?
* What happens when the operation is repeated?

Create additional requirements for every mandatory implied behavior.

---

# 9. Interface specification rules

Every interface MUST define:

* interface identifier;
* caller;
* callee;
* operation name;
* input fields;
* output fields;
* field types;
* valid ranges;
* units;
* ownership;
* allocation responsibility;
* deallocation responsibility;
* mutability;
* thread-safety;
* blocking behavior;
* ordering guarantees;
* error codes;
* retry behavior;
* timeout behavior;
* versioning;
* compatibility rules.

Do not write “returns an error” without defining the error domain and exact conditions.

Example:

```text
API-SHARD-004:
assign_fact_owner() MUST return ERR_INVALID_GPU_COUNT when num_gpus equals zero.
```

---

# 10. Data specification rules

Every persistent or transmitted data structure MUST define:

* schema identifier;
* field names;
* field order;
* field types;
* signedness;
* bit width;
* byte order;
* alignment;
* optionality;
* default value;
* valid range;
* reserved values;
* invariant constraints;
* ownership;
* lifetime;
* serialization;
* versioning;
* compatibility behavior.

For identifier fields, define:

* uniqueness domain;
* generation method;
* collision policy;
* stable lifetime;
* canonical representation.

---

# 11. State-machine requirements

Whenever behavior depends on lifecycle or sequencing, define an explicit state machine.

For every state machine, provide:

* state identifiers;
* initial state;
* terminal states;
* valid transitions;
* transition triggers;
* transition guards;
* state mutations;
* invalid-transition behavior;
* recovery transitions;
* idempotency rules.

Every mandatory transition MUST receive its own requirement ID or explicitly reference one atomic transition-table entry.

Do not describe stateful behavior only in prose.

---

# 12. Algorithm specification rules

Each required algorithm MUST define:

* algorithm identifier;
* mathematical definition;
* input domain;
* output domain;
* invariants;
* termination condition;
* ordering rules;
* tie-breaking rules;
* complexity target;
* error conditions;
* deterministic behavior;
* pseudocode;
* acceptance tests.

Example:

[
\Delta H =
\operatorname{Unique}
\left(
\pi_H
\left(
\Join_i \operatorname{Match}(A_i,R_i)
\right)
\right)
-------

H_{\text{known}}
]

This equation alone is insufficient.

The specification must separately define:

* `Match`;
* join semantics;
* join ordering requirements;
* projection semantics;
* uniqueness identity;
* subtraction semantics;
* treatment of duplicates;
* treatment of existing facts;
* output ordering;
* empty-input behavior;
* distributed execution behavior;
* termination behavior.

---

# 13. Determinism requirements

For every operation that must be deterministic, define the determinism boundary.

Specify which of the following must remain identical:

* logical result set;
* ordered result sequence;
* serialized output bytes;
* logs;
* output hashes;
* execution trace;
* timing;
* memory layout.

Do not use “deterministic” without defining which observable properties are constrained.

Also specify which inputs are included in the deterministic execution identity:

```text
input bytes
configuration
executable hash
compiler version
hardware class
GPU count
initial state
environment variables
dataset version
```

---

# 14. Error and boundary requirements

For every functional requirement, derive corresponding cases for:

* zero input;
* one input;
* maximum supported input;
* input beyond the maximum;
* malformed input;
* duplicate input;
* missing input;
* unsupported version;
* unavailable resource;
* allocation failure;
* interrupted operation;
* partial operation;
* repeated operation;
* invalid state;
* dependency failure;
* timeout;
* overflow;
* underflow;
* concurrent invocation.

Only include applicable cases, but explicitly mark irrelevant cases as not applicable.

---

# 15. Requirement hierarchy

Organize the specification into the following hierarchy:

```text
System goals
	↓
Capabilities
	↓
Subsystem requirements
	↓
Component requirements
	↓
Interface requirements
	↓
Algorithm and data requirements
	↓
Error and boundary requirements
	↓
Verification requirements
```

Higher-level requirements may summarize behavior, but they MUST NOT replace lower-level atomic requirements.

A parent requirement is complete only when all mandatory child requirements pass.

Formally:

[
\operatorname{Complete}(R_p)
\iff
\forall R_c \in \operatorname{MandatoryChildren}(R_p),
\operatorname{Complete}(R_c)
]

---

# 16. Explicit non-requirements

Create a section named `Non-Requirements and Excluded Scope`.

Every material feature that might reasonably be assumed but is intentionally excluded must be listed.

Examples:

```text
OUT-SCOPE-001:
Automatic recovery after physical GPU removal is not required in this phase.

OUT-SCOPE-002:
Compatibility with non-ROCm GPU platforms is not required.

OUT-SCOPE-003:
Dynamic addition of GPUs during execution is not required.
```

Non-requirements prevent auditors from expanding the specification boundary.

---

# 17. Assumptions and unresolved decisions

Maintain separate registries for:

```text
ASSUMPTIONS
OPEN QUESTIONS
DECISIONS
RISKS
CONSTRAINTS
```

Every entry must have an identifier.

Examples:

```text
ASM-HW-001
QRY-SHARD-003
DEC-HASH-002
RISK-MEM-004
CON-OS-001
```

An unresolved question MUST NOT be silently converted into a requirement.

If an implementation decision is required before work can begin, mark affected requirements as blocked.

---

# 18. Prohibition against premature implementation detail

Specify externally necessary design constraints, but do not prescribe internal implementation details unless they are required for:

* correctness;
* interoperability;
* determinism;
* performance;
* compatibility;
* safety;
* formal verification.

Bad:

> Use a linked list for the candidate fact queue.

Better:

> Candidate insertion MUST have amortized (O(1)) time under benchmark workload `BENCH-WORKLOAD-002`.

Prescribe the linked list only when another requirement depends on that exact representation.

---

# 19. Test specification

Each test must have a stable identifier and contain:

```text
Test ID:
Title:
Requirement coverage:
Test level:
Preconditions:
Fixture:
Input:
Execution procedure:
Expected output:
Expected state change:
Expected errors:
Pass condition:
Failure condition:
Repeat count:
Determinism constraints:
Evidence produced:
Cleanup procedure:
```

Use test IDs such as:

```text
UT-DELTA-001
IT-SHARD-004
ST-MULTIGPU-002
PT-HASH-003
BENCH-JOIN-001
```

Tests must not rely on unstated human judgment.

---

# 20. Coverage matrices

Produce the following matrices.

## 20.1 Requirements coverage matrix

| Requirement ID | Parent goal | Component | Verification method | Test IDs | Evidence | Status |
| -------------- | ----------- | --------- | ------------------- | -------- | -------- | ------ |

## 20.2 Interface coverage matrix

| Interface ID | Caller | Callee | Related requirements | Success tests | Failure tests |
| ------------ | ------ | ------ | -------------------- | ------------- | ------------- |

## 20.3 Data coverage matrix

| Schema ID | Producer | Consumers | Validation requirements | Serialization tests |
| --------- | -------- | --------- | ----------------------- | ------------------- |

## 20.4 State-transition coverage matrix

| State machine | Transition | Requirement ID | Positive test | Invalid-transition test |
| ------------- | ---------- | -------------- | ------------- | ----------------------- |

## 20.5 Error coverage matrix

| Error code | Trigger condition | Requirement ID | Test ID | Recovery behavior |
| ---------- | ----------------- | -------------- | ------- | ----------------- |

---

# 21. Completeness calculation

Do not estimate completeness subjectively.

Specification completeness must be calculated from explicit checks.

For mandatory approved requirements:

[
C_{\text{traceability}}
=======================

\frac{
N_{\text{requirements with goal, component, verification, and evidence links}}
}{
N_{\text{mandatory requirements}}
}
]

[
C_{\text{acceptance}}
=====================

\frac{
N_{\text{requirements with binary acceptance criteria}}
}{
N_{\text{mandatory requirements}}
}
]

[
C_{\text{test coverage}}
========================

\frac{
N_{\text{requirements with an approved verification method}}
}{
N_{\text{mandatory requirements}}
}
]

The specification is ready for implementation only when:

```text
Traceability coverage		= 100%
Acceptance coverage		= 100%
Verification coverage		= 100%
Unidentified MUST statements	= 0
Orphan requirements		= 0
Orphan tests			= 0
Unresolved critical questions	= 0
Compound mandatory requirements	= 0
```

---

# 22. Mandatory atomicity audit

Before finalizing the specification, inspect every normative requirement using this checklist.

For each requirement, answer:

```text
1. Does it contain exactly one obligation?
2. Can it independently pass or fail?
3. Does it contain an ambiguous adjective?
4. Does it contain an undefined term?
5. Does it contain “and” joining independent behaviors?
6. Does it contain an implicit error case?
7. Does it depend on an unstated precondition?
8. Does it define observable evidence?
9. Does it have a binary acceptance criterion?
10. Does it trace to a parent goal?
11. Does it identify a responsible component?
12. Does it identify a verification method?
13. Does it conflict with another requirement?
14. Can an implementer determine when work is finished?
15. Can an auditor verify it without inventing new criteria?
```

Any requirement failing one of these checks must be revised or explicitly justified.

---

# 23. Terminology control

Create a normative glossary.

Every domain term must have exactly one canonical definition.

For each term, define:

```text
Term ID:
Canonical term:
Definition:
Type:
Allowed synonyms:
Disallowed ambiguous uses:
Related terms:
```

The same term must not have different meanings in different sections.

Different concepts must not share the same term.

All requirement text must use canonical terminology.

---

# 24. Change control

Every specification revision must include:

* specification version;
* date;
* changed requirement IDs;
* added requirement IDs;
* deleted or retired requirement IDs;
* previous wording;
* new wording;
* reason for change;
* affected tests;
* affected interfaces;
* compatibility impact.

Do not renumber existing requirements after insertion or deletion.

A specification revision must not silently change the acceptance boundary.

---

# 25. Required document sections

Produce the final specification in this order:

```text
1. Document metadata
2. Revision history
3. System purpose
4. Scope
5. Non-requirements and excluded scope
6. Normative terminology
7. Glossary
8. Assumptions
9. Constraints
10. Decisions
11. Open questions
12. Risks
13. System goals
14. Architecture
15. Component definitions
16. Functional requirements
17. Data requirements
18. Algorithm requirements
19. State-machine requirements
20. Interface requirements
21. Determinism requirements
22. Error and boundary requirements
23. Performance requirements
24. Concurrency requirements
25. Observability requirements
26. Build and platform requirements
27. Extension and compatibility requirements
28. Test specifications
29. Acceptance criteria
30. Traceability matrices
31. Compliance calculation
32. Atomicity audit results
33. Unresolved blockers
34. Appendices
```

---

# 26. Required machine-readable companion artifact

In addition to the human-readable document, produce a machine-readable requirement registry.

Use a structure equivalent to:

```text
requirement:
	id
	title
	category
	normative_statement
	rationale
	source
	parent_goals[]
	dependencies[]
	related_requirements[]
	components[]
	preconditions[]
	inputs[]
	outputs[]
	state_changes[]
	failure_behavior[]
	acceptance_criteria[]
	verification_methods[]
	test_ids[]
	evidence[]
	priority
	applicability
	status
```

The machine-readable artifact must contain the same normative requirements as the human-readable document.

The two representations must not contain conflicting requirement text.

---

# 27. Final validation procedure

Before delivering the specification, perform the following validation sequence:

```text
1. Extract every sentence containing MUST or MUST NOT.
2. Confirm that every extracted sentence has a requirement ID.
3. Detect compound obligations.
4. Detect undefined terminology.
5. Detect requirements without parent goals.
6. Detect requirements without responsible components.
7. Detect requirements without acceptance criteria.
8. Detect requirements without verification methods.
9. Detect tests without linked requirements.
10. Detect requirements without linked tests or approved alternative verification.
11. Detect cyclic requirement dependencies.
12. Detect contradictory requirements.
13. Detect requirements relying on unresolved questions.
14. Detect informative prose that appears to introduce hidden obligations.
15. Generate all traceability matrices.
16. Calculate coverage metrics.
17. Revise until every required coverage metric equals 100%.
```

---

# 28. Output constraints

The final document MUST NOT:

* combine multiple independently testable obligations into one requirement;
* use subjective completeness percentages;
* invent requirements during the audit section;
* hide mandatory behavior in examples;
* use undefined terms;
* leave mandatory error behavior unspecified;
* classify missing evidence as equivalent to missing implementation;
* mix current-phase requirements with future possibilities;
* treat recommendations as compliance obligations;
* use open-ended phrases without measurable bounds.

---

# 29. Final delivery package

Deliver all of the following:

```text
A. Human-readable specification
B. Machine-readable requirement registry
C. Requirement hierarchy
D. Goal-to-requirement matrix
E. Requirement-to-component matrix
F. Requirement-to-test matrix
G. Interface coverage matrix
H. Data coverage matrix
I. State-transition coverage matrix
J. Error coverage matrix
K. Glossary
L. Assumption registry
M. Decision registry
N. Open-question registry
O. Risk registry
P. Non-requirements registry
Q. Atomicity audit report
R. Traceability coverage report
S. Specification completeness report
```

Do not declare the specification complete unless every mandatory requirement is atomic, testable, and bidirectionally traceable.

---

# 30. Governing completion rule

The specification is complete only when every mandatory system obligation can be represented as a finite proposition with a binary verification result.

Formally:

[
\operatorname{SpecificationReady}
\iff
\forall r \in R_{\text{mandatory}},
\quad
\operatorname{Atomic}(r)
\land
\operatorname{Unambiguous}(r)
\land
\operatorname{Traceable}(r)
\land
\operatorname{Verifiable}(r)
]

The specification must make it impossible for an implementer or auditor to substitute an informal impression for an explicit compliance result.
