PRAGMA foreign_keys = ON;
PRAGMA journal_mode = DELETE;

CREATE TABLE schema_metadata (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
) WITHOUT ROWID;

INSERT INTO schema_metadata(key, value) VALUES
    ('schema_name', 'coding-harness-repository-index'),
    ('schema_version', '5');

CREATE TABLE index_generations (
    generation_id TEXT PRIMARY KEY,
    repository_id TEXT NOT NULL,
    source_revision TEXT NOT NULL,
    compile_commands_sha256 TEXT NOT NULL,
    generated_inputs_sha256 TEXT NOT NULL,
    scip_clang_fingerprint TEXT NOT NULL,
    scip_fingerprint TEXT NOT NULL,
    importer_fingerprint TEXT NOT NULL,
    build_importer_fingerprint TEXT NOT NULL,
    schema_sha256 TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('BUILDING', 'READY', 'INVALID')),
    created_at TEXT NOT NULL
) WITHOUT ROWID;

CREATE TABLE build_configurations (
    configuration_id TEXT PRIMARY KEY,
    generation_id TEXT NOT NULL REFERENCES index_generations(generation_id),
    compile_commands_path TEXT NOT NULL,
    compile_commands_sha256 TEXT NOT NULL,
    compiler_family TEXT,
    target_triple TEXT,
    attributes_json TEXT NOT NULL DEFAULT '{}'
) WITHOUT ROWID;

CREATE TABLE files (
    file_id INTEGER PRIMARY KEY,
    generation_id TEXT NOT NULL REFERENCES index_generations(generation_id),
    repository_path TEXT NOT NULL,
    language TEXT,
    content_sha256 TEXT,
    tracked INTEGER NOT NULL DEFAULT 1 CHECK (tracked IN (0, 1)),
    generated INTEGER NOT NULL DEFAULT 0 CHECK (generated IN (0, 1)),
    UNIQUE(generation_id, repository_path)
);

CREATE TABLE source_regions (
    region_id INTEGER PRIMARY KEY,
    file_id INTEGER NOT NULL REFERENCES files(file_id),
    region_kind TEXT NOT NULL,
    name TEXT,
    start_line INTEGER NOT NULL CHECK (start_line > 0),
    start_column INTEGER NOT NULL DEFAULT 0 CHECK (start_column >= 0),
    end_line INTEGER NOT NULL CHECK (end_line >= start_line),
    end_column INTEGER NOT NULL DEFAULT 0 CHECK (end_column >= 0),
    content_sha256 TEXT,
    provider TEXT NOT NULL,
    UNIQUE(file_id, region_kind, start_line, start_column, end_line, end_column, provider)
);

CREATE TABLE symbols (
    symbol_id TEXT PRIMARY KEY,
    generation_id TEXT NOT NULL REFERENCES index_generations(generation_id),
    display_name TEXT NOT NULL,
    symbol_kind TEXT,
    language TEXT,
    package_name TEXT,
    provider TEXT NOT NULL
) WITHOUT ROWID;

CREATE TABLE symbol_definitions (
    symbol_id TEXT NOT NULL REFERENCES symbols(symbol_id),
    region_id INTEGER NOT NULL REFERENCES source_regions(region_id),
    definition_kind TEXT NOT NULL DEFAULT 'definition',
    provider TEXT NOT NULL,
    PRIMARY KEY(symbol_id, region_id, provider)
) WITHOUT ROWID;

CREATE TABLE symbol_references (
    symbol_id TEXT NOT NULL REFERENCES symbols(symbol_id),
    region_id INTEGER NOT NULL REFERENCES source_regions(region_id),
    reference_kind TEXT NOT NULL DEFAULT 'reference',
    provider TEXT NOT NULL,
    PRIMARY KEY(symbol_id, region_id, reference_kind, provider)
) WITHOUT ROWID;

CREATE TABLE symbol_edges (
    source_symbol_id TEXT NOT NULL REFERENCES symbols(symbol_id),
    target_symbol_id TEXT NOT NULL REFERENCES symbols(symbol_id),
    edge_kind TEXT NOT NULL,
    provider TEXT NOT NULL,
    confidence TEXT NOT NULL CHECK (confidence IN ('AUTHORITATIVE', 'DERIVED', 'HEURISTIC')),
    evidence_region_id INTEGER REFERENCES source_regions(region_id),
    PRIMARY KEY(source_symbol_id, target_symbol_id, edge_kind, provider)
) WITHOUT ROWID;

CREATE TABLE include_edges (
    source_file_id INTEGER NOT NULL REFERENCES files(file_id),
    target_path TEXT NOT NULL,
    resolved_file_id INTEGER REFERENCES files(file_id),
    provider TEXT NOT NULL,
    PRIMARY KEY(source_file_id, target_path, provider)
) WITHOUT ROWID;

CREATE TABLE call_edges (
    caller_symbol_id TEXT NOT NULL REFERENCES symbols(symbol_id),
    callee_symbol_id TEXT NOT NULL REFERENCES symbols(symbol_id),
    evidence_region_id INTEGER REFERENCES source_regions(region_id),
    provider TEXT NOT NULL,
    confidence TEXT NOT NULL CHECK (confidence IN ('AUTHORITATIVE', 'DERIVED', 'HEURISTIC')),
    PRIMARY KEY(caller_symbol_id, callee_symbol_id, provider)
) WITHOUT ROWID;

CREATE TABLE type_edges (
    source_symbol_id TEXT NOT NULL REFERENCES symbols(symbol_id),
    type_symbol_id TEXT NOT NULL REFERENCES symbols(symbol_id),
    edge_kind TEXT NOT NULL,
    provider TEXT NOT NULL,
    PRIMARY KEY(source_symbol_id, type_symbol_id, edge_kind, provider)
) WITHOUT ROWID;

CREATE TABLE control_flow_edges (
    source_region_id INTEGER NOT NULL REFERENCES source_regions(region_id),
    target_region_id INTEGER NOT NULL REFERENCES source_regions(region_id),
    edge_kind TEXT NOT NULL,
    provider TEXT NOT NULL,
    PRIMARY KEY(source_region_id, target_region_id, edge_kind, provider)
) WITHOUT ROWID;

CREATE TABLE data_flow_edges (
    source_region_id INTEGER NOT NULL REFERENCES source_regions(region_id),
    target_region_id INTEGER NOT NULL REFERENCES source_regions(region_id),
    value_name TEXT,
    edge_kind TEXT NOT NULL,
    provider TEXT NOT NULL,
    PRIMARY KEY(source_region_id, target_region_id, edge_kind, provider)
) WITHOUT ROWID;

CREATE TABLE modules (
    module_id TEXT PRIMARY KEY,
    generation_id TEXT NOT NULL REFERENCES index_generations(generation_id),
    name TEXT NOT NULL,
    module_kind TEXT NOT NULL,
    root_path TEXT,
    provider TEXT NOT NULL,
    authority TEXT NOT NULL CHECK (authority IN ('REGISTERED', 'DERIVED', 'PROPOSED'))
) WITHOUT ROWID;

CREATE TABLE module_edges (
    source_module_id TEXT NOT NULL REFERENCES modules(module_id),
    target_module_id TEXT NOT NULL REFERENCES modules(module_id),
    edge_kind TEXT NOT NULL,
    provider TEXT NOT NULL,
    evidence_count INTEGER NOT NULL DEFAULT 1 CHECK (evidence_count > 0),
    PRIMARY KEY(source_module_id, target_module_id, edge_kind, provider)
) WITHOUT ROWID;

CREATE TABLE concept_owners (
    concept_id TEXT NOT NULL,
    owner_kind TEXT NOT NULL CHECK (owner_kind IN ('MODULE', 'SYMBOL', 'FILE', 'EXTERNAL')),
    owner_id TEXT NOT NULL,
    authority TEXT NOT NULL CHECK (authority IN ('REGISTERED', 'DERIVED', 'PROPOSED')),
    provider TEXT NOT NULL,
    evidence TEXT NOT NULL,
    PRIMARY KEY(concept_id, owner_kind, owner_id, authority, provider)
) WITHOUT ROWID;

CREATE TABLE architecture_bindings (
    plan_node_id TEXT NOT NULL,
    binding_kind TEXT NOT NULL,
    binding_id TEXT NOT NULL,
    authority TEXT NOT NULL CHECK (authority IN ('SPECIFIED', 'DERIVED', 'PROPOSED')),
    provider TEXT NOT NULL,
    PRIMARY KEY(plan_node_id, binding_kind, binding_id, provider)
) WITHOUT ROWID;

CREATE TABLE invariants (
    invariant_id TEXT PRIMARY KEY,
    statement TEXT NOT NULL,
    authority TEXT NOT NULL CHECK (authority IN ('SPECIFIED', 'DERIVED', 'PROPOSED')),
    severity TEXT,
    validation TEXT,
    provider TEXT NOT NULL
) WITHOUT ROWID;

CREATE TABLE tests (
    test_id TEXT PRIMARY KEY,
    generation_id TEXT NOT NULL REFERENCES index_generations(generation_id),
    name TEXT NOT NULL,
    file_id INTEGER REFERENCES files(file_id),
    region_id INTEGER REFERENCES source_regions(region_id),
    build_target TEXT,
    selector TEXT,
    provider TEXT NOT NULL
) WITHOUT ROWID;

CREATE TABLE test_symbol_edges (
    test_id TEXT NOT NULL REFERENCES tests(test_id),
    symbol_id TEXT NOT NULL REFERENCES symbols(symbol_id),
    edge_kind TEXT NOT NULL,
    provider TEXT NOT NULL,
    PRIMARY KEY(test_id, symbol_id, edge_kind, provider)
) WITHOUT ROWID;

CREATE TABLE build_targets (
    target_id TEXT PRIMARY KEY,
    generation_id TEXT NOT NULL REFERENCES index_generations(generation_id),
    name TEXT NOT NULL,
    target_kind TEXT,
    definition_path TEXT,
    provider TEXT NOT NULL
) WITHOUT ROWID;

CREATE TABLE build_target_files (
    target_id TEXT NOT NULL REFERENCES build_targets(target_id),
    file_id INTEGER NOT NULL REFERENCES files(file_id),
    configuration_id TEXT NOT NULL REFERENCES build_configurations(configuration_id),
    role TEXT NOT NULL CHECK (role IN ('COMPILE_SOURCE', 'GENERATED_SOURCE')),
    object_path TEXT,
    provider TEXT NOT NULL,
    PRIMARY KEY(target_id, file_id, configuration_id, role, provider)
) WITHOUT ROWID;

CREATE TABLE build_inputs (
    input_id TEXT PRIMARY KEY,
    generation_id TEXT NOT NULL REFERENCES index_generations(generation_id),
    absolute_path TEXT NOT NULL,
    content_sha256 TEXT NOT NULL,
    input_kind TEXT NOT NULL CHECK (input_kind IN ('GENERATED_HEADER', 'EXTERNAL_HEADER')),
    provider TEXT NOT NULL,
    UNIQUE(generation_id, absolute_path, provider)
) WITHOUT ROWID;

CREATE TABLE build_target_inputs (
    target_id TEXT NOT NULL REFERENCES build_targets(target_id),
    input_id TEXT NOT NULL REFERENCES build_inputs(input_id),
    source_path TEXT NOT NULL,
    include_literal TEXT NOT NULL,
    included_by TEXT NOT NULL,
    provider TEXT NOT NULL,
    PRIMARY KEY(target_id, input_id, source_path, include_literal, provider)
) WITHOUT ROWID;

CREATE TABLE provider_runs (
    provider TEXT NOT NULL,
    generation_id TEXT NOT NULL REFERENCES index_generations(generation_id),
    provider_version TEXT NOT NULL,
    fingerprint TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('READY', 'DEGRADED', 'UNAVAILABLE', 'FAILED')),
    evidence_path TEXT,
    recorded_at TEXT NOT NULL,
    PRIMARY KEY(provider, generation_id)
) WITHOUT ROWID;

CREATE TABLE diagnostics (
    diagnostic_id TEXT PRIMARY KEY,
    generation_id TEXT NOT NULL REFERENCES index_generations(generation_id),
    provider TEXT NOT NULL,
    severity TEXT NOT NULL,
    code TEXT,
    message TEXT NOT NULL,
    repository_path TEXT,
    start_line INTEGER,
    end_line INTEGER,
    configuration_id TEXT
) WITHOUT ROWID;

CREATE TABLE mutation_edges (
    source_symbol_id TEXT NOT NULL REFERENCES symbols(symbol_id),
    target_symbol_id TEXT,
    target_value TEXT,
    evidence_region_id INTEGER REFERENCES source_regions(region_id),
    provider TEXT NOT NULL,
    confidence TEXT NOT NULL CHECK (confidence IN ('AUTHORITATIVE', 'DERIVED', 'HEURISTIC')),
    PRIMARY KEY(source_symbol_id, target_symbol_id, target_value, provider)
) WITHOUT ROWID;

CREATE TABLE architecture_findings (
    finding_id TEXT PRIMARY KEY,
    generation_id TEXT NOT NULL REFERENCES index_generations(generation_id),
    finding_kind TEXT NOT NULL,
    severity TEXT NOT NULL,
    subject_id TEXT NOT NULL,
    evidence TEXT NOT NULL,
    authority TEXT NOT NULL CHECK (authority IN ('REGISTERED', 'DERIVED', 'PROPOSED')),
    provider TEXT NOT NULL
) WITHOUT ROWID;

CREATE TABLE architecture_benchmarks (
    benchmark_id TEXT NOT NULL,
    generation_id TEXT NOT NULL REFERENCES index_generations(generation_id),
    query TEXT NOT NULL,
    expected_paths TEXT NOT NULL,
    returned_paths TEXT NOT NULL,
    relevant_returned INTEGER NOT NULL,
    expected_total INTEGER NOT NULL,
    returned_total INTEGER NOT NULL,
    context_bytes INTEGER NOT NULL,
    provider TEXT NOT NULL,
    PRIMARY KEY(benchmark_id, generation_id)
) WITHOUT ROWID;

CREATE TABLE facts (
    fact_id TEXT PRIMARY KEY,
    generation_id TEXT NOT NULL REFERENCES index_generations(generation_id),
    fact_kind TEXT NOT NULL,
    subject_id TEXT NOT NULL,
    predicate TEXT NOT NULL,
    object_value TEXT NOT NULL,
    authority TEXT NOT NULL CHECK (authority IN ('AUTHORITATIVE', 'DERIVED', 'HEURISTIC'))
) WITHOUT ROWID;

CREATE TABLE fact_provenance (
    fact_id TEXT NOT NULL REFERENCES facts(fact_id),
    provider TEXT NOT NULL,
    provider_version TEXT,
    configuration_id TEXT,
    source_path TEXT,
    source_region TEXT,
    evidence_sha256 TEXT,
    PRIMARY KEY(fact_id, provider)
) WITHOUT ROWID;

CREATE VIRTUAL TABLE lexical_documents USING fts5(
    document_id UNINDEXED,
    repository_path UNINDEXED,
    symbol_name,
    document_kind UNINDEXED,
    content,
    tokenize = 'unicode61'
);

CREATE INDEX files_generation_path_idx ON files(generation_id, repository_path);
CREATE INDEX regions_file_lines_idx ON source_regions(file_id, start_line, end_line);
CREATE INDEX symbols_generation_name_idx ON symbols(generation_id, display_name);
CREATE INDEX facts_subject_predicate_idx ON facts(subject_id, predicate);
CREATE INDEX build_target_files_file_idx ON build_target_files(file_id, target_id);

PRAGMA user_version = 5;
