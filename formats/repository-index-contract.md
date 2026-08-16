# Repository Index Contract

The repository index is a deterministic, provenance-bearing input to
decomposition and Context Closure. It is not product authority and cannot
override the specification or registered architecture.

## Identity

An immutable generation is identified by:

- repository Git common-directory identity;
- committed source revision;
- normalized compilation-database hash;
- deterministic direct generated/external compilation-input hash;
- repository-index schema content hash and version;
- `scip-clang` fingerprint;
- SCIP CLI fingerprint;
- compiled SCIP importer fingerprint.
- compilation-database/build-target importer fingerprint.

Joern and lexical-provider fingerprints will join the generation identity when
their data is first admitted into the canonical database.

Two harness projects using the same Git repository, revision, configuration,
schema, and tools may reuse one generation. A changed configuration must create
a different generation even when source revision is unchanged.

## Freshness

The initial implementation indexes committed tracked source and requires a
clean tracked worktree. Untracked repository files are not indexed. Direct
headers resolved outside the repository through compilation-command include
paths are hashed into generation identity and mapped to their build target;
changing one invalidates the project pointer. Transitive external includes and
worktree-overlay indexing remain required-mode qualification work.

## Publication

Index construction occurs in a private temporary generation directory under a
per-repository lock. The builder validates the SCIP artifact, SQLite schema,
and database integrity before writing `status=READY` and atomically publishing
the immutable generation. A project pointer is replaced only after publication.

`scip lint` findings are retained with their exit status. They are quality
evidence rather than a protobuf-validity verdict: current indexers may report
incomplete local-symbol metadata while still producing structurally consumable
definitions and references. Required Context Closure must evaluate unresolved
facts at the selected leaf instead of treating every global lint finding as a
fatal index error.

Compilation units are mapped to build owners from the normalized compilation
database. CMake object paths provide exact target names when available; other
build systems receive a deterministic translation-unit owner. Every mapping
retains its configuration, object path, provider, and nearest discoverable
build definition. This is derived navigation evidence, not ownership authority.

An interrupted or failed build must leave the prior project pointer unchanged.

## Authority

Evidence classes are:

- `AUTHORITATIVE`: compiler/protocol-resolved structural evidence;
- `DERIVED`: deterministic projection from authoritative facts;
- `HEURISTIC`: lexical or similarity candidate evidence;
- registered architecture and specification authority, stored separately and
  always taking precedence over inferred implementation structure.

Absence of an edge from an unsupported provider is `UNKNOWN`, not proof that no
dependency exists.

## Location

Generated artifacts live under `HARNESS_REPOSITORY_INDEX_ROOT`, which defaults
to `$HARNESS_ROOT/repository-indexes`. The source repository is never used as an
index output directory.
