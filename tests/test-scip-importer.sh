#!/usr/bin/env bash

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_HOME="$(cd "$SCRIPT_DIR/.." && pwd)"

for required in cmake go scip scip-clang sqlite3; do
	if ! command -v "$required" >/dev/null 2>&1; then
		printf 'scip importer integration test skipped: %s is unavailable\n' "$required"
		exit 0
	fi
done

TEST_ROOT="$(mktemp -d /tmp/harness-scip-importer.XXXXXX)"
if [[ "${HARNESS_TEST_KEEP_TMP:-0}" == 1 ]]; then
	trap 'printf "Preserved test root: %s\n" "$TEST_ROOT" >&2' EXIT
else
	cleanup_test_root() { result=$?; trap - EXIT; rm -rf -- "$TEST_ROOT"; exit "$result"; }
	trap cleanup_test_root EXIT
fi

"$HARNESS_HOME/bin/harness-build-index-tools" "$TEST_ROOT/tools" >/dev/null
importer="$TEST_ROOT/tools/harness-scip-importer"
test "$($importer --version)" = 'harness-scip-importer schema-v5'
cmake -S "$SCRIPT_DIR/fixtures/context-index-c" -B "$TEST_ROOT/build" \
	-DCMAKE_EXPORT_COMPILE_COMMANDS=ON >/dev/null
scip-clang --compdb-path "$TEST_ROOT/build/compile_commands.json" \
	--index-output-path "$TEST_ROOT/index.scip" --jobs 1 --no-progress-report \
	> "$TEST_ROOT/scip-clang.log" 2>&1
set +e
scip lint "$TEST_ROOT/index.scip" > "$TEST_ROOT/scip-lint.log" 2>&1
lint_status=$?
set -e
[[ "$lint_status" =~ ^[0-9]+$ ]]

database="$TEST_ROOT/architecture.sqlite"
sqlite3 "$database" < "$HARNESS_HOME/formats/repository-index-schema.sql" >/dev/null
sqlite3 "$database" \
	"INSERT INTO index_generations VALUES('fixture-generation','fixture-repository','fixture-revision','fixture-compdb','fixture-generated-inputs','fixture-scip-clang','fixture-scip','fixture-importer','fixture-build-importer','fixture-schema','READY','2026-08-16T00:00:00Z');"
"$importer" --index "$TEST_ROOT/index.scip" --database "$database" \
	--generation fixture-generation \
	--repository "$SCRIPT_DIR/fixtures/context-index-c" \
	--report "$TEST_ROOT/import.tsv" \
	--unresolved-report "$TEST_ROOT/unresolved-documents.tsv"

grep -Eq $'^documents\t7$' "$TEST_ROOT/import.tsv"
grep -Eq $'^skipped_documents\t0$' "$TEST_ROOT/import.tsv"
test "$(sqlite3 "$database" "SELECT count(*) FROM symbols WHERE display_name='context_add';")" -ge 1
test "$(sqlite3 "$database" "SELECT count(*) FROM symbols WHERE display_name='context_add' AND language != ''; ")" -ge 1
test "$(sqlite3 "$database" "SELECT count(*) FROM source_regions JOIN files USING(file_id) WHERE repository_path='src/calc.c' AND region_kind='symbol_definition';")" -ge 1
test "$(sqlite3 "$database" "SELECT count(*) FROM lexical_documents WHERE lexical_documents MATCH 'context_add';")" -ge 1
test "$(sqlite3 "$database" 'SELECT count(*) FROM symbol_references;')" -ge 1
test "$(sqlite3 "$database" "SELECT count(*) FROM test_symbol_edges JOIN symbols USING(symbol_id) WHERE display_name='context_add' AND edge_kind='REFERENCES';")" -ge 1
test "$(sqlite3 "$database" 'PRAGMA integrity_check;')" = ok

# Exercise the complete harness lifecycle with the real indexer, validator,
# generated-bindings importer, canonical database, and atomic pointer.
cp -a "$SCRIPT_DIR/fixtures/context-index-c" "$TEST_ROOT/repo"
git -C "$TEST_ROOT/repo" init -q
git -C "$TEST_ROOT/repo" add .
git -C "$TEST_ROOT/repo" -c user.name=test -c user.email=test@example.invalid commit -qm seed
cmake -S "$TEST_ROOT/repo" -B "$TEST_ROOT/e2e-build" -DCMAKE_EXPORT_COMPILE_COMMANDS=ON >/dev/null
mkdir -p "$TEST_ROOT/manager-home" "$TEST_ROOT/worker-home"
cat > "$TEST_ROOT/e2e.env" <<ENV
export PROJECT="scip-e2e"
export REPOSITORY="$TEST_ROOT/repo"
export SPECIFICATION="$TEST_ROOT/repo/spec.md"
export HARNESS_MODE="full"
export HARNESS_HOME="$HARNESS_HOME"
export HARNESS_BIN="$HARNESS_HOME/bin"
export HARNESS_ROOT="$TEST_ROOT/state"
export HARNESS_AGENT_MIN_INTERVAL_SECONDS="0"
export MANAGER_CODEX_HOME="$TEST_ROOT/manager-home"
export MANAGER_CODEX_BIN="/bin/true"
export WORKER_CODEX_HOME="$TEST_ROOT/worker-home"
export WORKER_CODEX_BIN="/bin/true"
export MANAGER_MODEL="gpt-5.6-terra"
export WORKER_MODEL="gpt-5.6-luna"
export LUNA_WORKER_MODEL="gpt-5.6-luna"
export TERRA_WORKER_MODEL="gpt-5.6-terra"
export DECOMPOSITION_MODEL="gpt-5.6-sol"
export HARNESS_DECOMPOSITION_V2="0"
export HARNESS_DECOMPOSITION_CRITIC_ENABLED="0"
export HARNESS_SPECIFICATION_REVIEW_ENABLED="0"
export HARNESS_ARCHITECTURE_GUARDS="0"
export HARNESS_REPOSITORY_INDEX_MODE="advisory"
export HARNESS_CONTEXT_CLOSURE_MODE="off"
export HARNESS_COMPILE_COMMANDS="$TEST_ROOT/e2e-build/compile_commands.json"
export HARNESS_SCIP_CLANG_BIN="$(command -v scip-clang)"
export HARNESS_SCIP_BIN="$(command -v scip)"
export HARNESS_SCIP_IMPORTER_BIN="$importer"
export HARNESS_SCIP_CLANG_JOBS="1"
export MAX_ORACLE_RUNS="0"
ENV
chmod 600 "$TEST_ROOT/e2e.env"
"$HARNESS_HOME/bin/harness-init" "$TEST_ROOT/e2e.env" >/dev/null
e2e_output="$($HARNESS_HOME/bin/harness-index-repository "$TEST_ROOT/e2e.env")"
grep -Fq 'INDEX_READY generation=' <<< "$e2e_output"
e2e_pointer="$TEST_ROOT/state/projects/scip-e2e/control/repository-index.env"
e2e_generation_dir="$(awk -F= '$1=="generation_dir" {print $2}' "$e2e_pointer")"
test "$(sqlite3 "$e2e_generation_dir/architecture.sqlite" "SELECT count(*) FROM symbols WHERE display_name='context_add';")" -ge 1
test "$(sqlite3 "$e2e_generation_dir/architecture.sqlite" 'SELECT count(*) FROM build_targets;')" = 6
test "$(sqlite3 "$e2e_generation_dir/architecture.sqlite" 'SELECT count(*) FROM build_target_files;')" = 6
test "$(sqlite3 "$e2e_generation_dir/architecture.sqlite" 'SELECT count(*) FROM build_inputs;')" = 2
test "$(sqlite3 "$e2e_generation_dir/architecture.sqlite" "SELECT count(*) FROM build_inputs WHERE input_kind='GENERATED_HEADER' AND absolute_path LIKE '%/generated/context_generated.hpp';")" = 1
test "$(sqlite3 "$e2e_generation_dir/architecture.sqlite" "SELECT count(*) FROM build_targets WHERE name='context_calc' AND definition_path='CMakeLists.txt';")" = 1
test "$(sqlite3 "$e2e_generation_dir/architecture.sqlite" "SELECT count(*) FROM tests WHERE build_target='context_calc_test';")" -ge 1
test "$(sqlite3 "$e2e_generation_dir/architecture.sqlite" 'SELECT count(*) FROM tests;')" -le 2
test "$(sqlite3 "$e2e_generation_dir/architecture.sqlite" "SELECT count(*) FROM tests WHERE name LIKE 'local %';")" = 0
test -s "$e2e_generation_dir/reports/scip-import.tsv"
grep -Eq $'^build_targets\t6$' "$e2e_generation_dir/reports/build-target-import.tsv"
grep -Eq $'^build_target_inputs\t2$' "$e2e_generation_dir/reports/build-target-import.tsv"
test -s "$e2e_generation_dir/reports/scip-lint.status"
test "$(sqlite3 "$e2e_generation_dir/architecture.sqlite" "SELECT status FROM provider_runs WHERE provider='joern';")" = UNAVAILABLE
test "$(sqlite3 "$e2e_generation_dir/architecture.sqlite" "SELECT status FROM provider_runs WHERE provider='recoll';")" = UNAVAILABLE

# Generated inputs outside Git participate in freshness and generation identity.
generated_header="$TEST_ROOT/e2e-build/generated/context_generated.hpp"
cp "$generated_header" "$TEST_ROOT/context_generated.hpp.saved"
sed -i 's/+ 7/+ 9/' "$generated_header"
if "$HARNESS_HOME/bin/harness-query-architecture" "$TEST_ROOT/e2e.env" context_add \
	> "$TEST_ROOT/generated-stale-query.out" 2>&1; then
	printf 'architecture query accepted a changed generated header\n' >&2
	exit 1
fi
grep -Fq 'generated-inputs-changed' "$TEST_ROOT/generated-stale-query.out"
mv "$TEST_ROOT/context_generated.hpp.saved" "$generated_header"
architecture_slice="$TEST_ROOT/repository-architecture-slice.md"
"$HARNESS_HOME/bin/harness-export-architecture-slice" \
	"$TEST_ROOT/e2e.env" "$architecture_slice" >/dev/null
grep -Fq '`context_calc_cpp` (CMAKE_COMPILE_TARGET)' "$architecture_slice"
grep -Fq '## Public interface candidates' "$architecture_slice"
grep -Fq '`context_scale` — `include/calc.hpp`' "$architecture_slice"
test "$(wc -c < "$architecture_slice")" -le 32768

# Compile a deterministic Context Closure from authoritative structural seeds.
cat > "$TEST_ROOT/context-assignment.md" <<'ASSIGNMENT'
Task-ID: context-add-test
Plan-Node: n01
Worker-Route: LUNA
Deliverable: Preserve addition behavior and its public declaration.
Acceptance-Evidence: context_index_test exits successfully.
Focused-Validation: cmake --build BUILD && ctest --test-dir BUILD
Allowed-Scope: src/calc.c,include/calc.h,tests/test_calc.c
Context-Paths: src/calc.c,include/calc.h,tests/test_calc.c
Required-Symbols: context_add
Architecture-Decisions: NONE
Affected-Invariants: addition returns the mathematical sum
Edge-Contracts: public declaration remains compatible
Baseline-Boundary: committed fixture revision
ASSIGNMENT
closure_output="$($HARNESS_HOME/bin/harness-build-context-closure \
	"$TEST_ROOT/e2e.env" "$TEST_ROOT/context-assignment.md")"
grep -Fq 'CONTEXT_CLOSURE status=READY task=context-add-test' <<< "$closure_output"
closure_dir="$TEST_ROOT/state/projects/scip-e2e/control/context-closures/scip-e2e-task-context-add-test"
test -s "$closure_dir/context.md"
test -s "$closure_dir/closure.tsv"
grep -Fq 'context_add' "$closure_dir/context.md"
grep -Fq 'return left + right;' "$closure_dir/context.md"
grep -Fq 'return context_add(2, 3) == 5 ? 0 : 1;' "$closure_dir/context.md"
grep -Fq $'FOCUSED_TEST\ttests/test_calc.c' "$closure_dir/closure.tsv"
grep -Eq $'^status\tREADY$' "$closure_dir/quality.tsv"
grep -Eq $'^unresolved\t0$' "$closure_dir/quality.tsv"
grep -Eq $'^build_targets\t2$' "$closure_dir/quality.tsv"
grep -Fq $'context_calc\tCMAKE_COMPILE_TARGET\tCMakeLists.txt' "$closure_dir/build-targets.tsv"
grep -Fq $'BUILD_TARGET\tbuild-target:context_calc\t' "$closure_dir/suggested-cuts.tsv"
grep -Fq $'BUILD_TARGET\tbuild-target:context_calc_test\t' "$closure_dir/suggested-cuts.tsv"

# Proposed Luna leaves can be dry-run against the same exact graph before any
# worker starts. The report carries measured bounds and cohesive child seams.
cat > "$TEST_ROOT/candidate-dag.tsv" <<'TSV'
node_id	parent_id	depends_on	deliverable	acceptance_evidence	focused_validation	allowed_paths	required_symbols	leaf_type	complexity_class	worker_route	behavioral_concerns	failure_paths	ownership_transitions	concurrency_boundaries	validation_surfaces	implementation_files	predicted_worker_actions	predicted_p95_tokens	terra_exception
n01	-	-	Preserve addition behavior and its declaration.	context_index_test exits successfully.	ctest --test-dir BUILD	src/calc.c,include/calc.h,tests/test_calc.c	context_add	LOCAL_IMPLEMENTATION	LOW	LUNA	1	1	1	1	1	2	6	60000	-
TSV
cat > "$TEST_ROOT/candidate-coverage.tsv" <<'TSV'
obligation_id	node_ids	evidence_plan
REQ-1	n01	focused context_index_test
TSV
evaluation_output="$($HARNESS_HOME/bin/harness-evaluate-decomposition-context \
	"$TEST_ROOT/e2e.env" "$TEST_ROOT/candidate-dag.tsv" "$TEST_ROOT/candidate-coverage.tsv" \
	- "$TEST_ROOT/context-admission")"
grep -Fq 'DECOMPOSITION_CONTEXT_EVALUATED' <<< "$evaluation_output"
grep -Eq $'^n01\tLUNA\tREADY\t' "$TEST_ROOT/context-admission/admission.tsv"
grep -Eq $'^n01\t[^\t]+\tBUILD_TARGET\tbuild-target:context_calc\t' \
	"$TEST_ROOT/context-admission/suggested-cuts.tsv"

# Advisory usage comparison identifies evidence referenced by the worker and
# repository paths discovered outside the compiled closure without enforcing.
cat > "$TEST_ROOT/worker.jsonl" <<'JSONL'
{"type":"item.completed","item":{"type":"command_execution","command":"sed -n '1,80p' src/calc.c && sed -n '1,80p' CMakeLists.txt","aggregated_output":"bounded"}}
{"type":"item.completed","item":{"type":"file_change","changes":[{"path":"tests/test_calc.c"}]}}
JSONL
usage_output="$($HARNESS_HOME/bin/harness-context-closure-usage \
	"$TEST_ROOT/e2e.env" context-add-test "$TEST_ROOT/worker.jsonl")"
usage_report="$(sed -n 's/^report=//p' <<< "$usage_output")"
grep -Fq $'src/calc.c\tIN_CLOSURE\tREQUIRED\t1\t0\tUSED' "$usage_report"
grep -Fq $'tests/test_calc.c\tIN_CLOSURE\tREQUIRED\t1\t1\tUSED' "$usage_report"
grep -Fq $'CMakeLists.txt\tOUTSIDE_CLOSURE\t-\t1\t0\tMISSING_CANDIDATE' "$usage_report"
grep -Eq '^missing_candidates=1$' "${usage_report%.tsv}.env"
bash -c 'source "$1/lib/harness-common.sh"; load_harness_env "$2"; ensure_project; record_context_closure_outcome context-add-test ACCEPTED n01' \
	_ "$HARNESS_HOME" "$TEST_ROOT/e2e.env"
grep -Eq $'\tcontext-add-test\tACCEPTED\t.*\t1\t3\t2\t1\t1\t0\tREADY$' \
	"$TEST_ROOT/state/projects/scip-e2e/logs/context-closure-outcomes.tsv"
baseline_output="$($HARNESS_HOME/bin/harness-context-baseline "$TEST_ROOT/e2e.env")"
grep -Fq $'context_closure_reviewed_episodes\t1' <<< "$baseline_output"
grep -Fq $'context_closure_missing_candidates\t1' <<< "$baseline_output"
"$HARNESS_HOME/bin/harness-context-closure-check" \
	"$TEST_ROOT/e2e.env" context-add-test >/dev/null
query_output="$($HARNESS_HOME/bin/harness-query-architecture \
	"$TEST_ROOT/e2e.env" context_add)"
grep -Eq $'^DEFINITION\tcontext_add\tsrc/calc.c\t' <<< "$query_output"
show_output="$($HARNESS_HOME/bin/harness-show-context-closure \
	"$TEST_ROOT/e2e.env" context-add-test)"
grep -Fq '# Compiled Context Closure' <<< "$show_output"
why_output="$($HARNESS_HOME/bin/harness-show-context-closure \
	"$TEST_ROOT/e2e.env" context-add-test --why context_add)"
grep -Eq $'DEFINITION\tsrc/calc.c\t.*\tcontext_add\tassignment required symbol: context_add' \
	<<< "$why_output"

# Rebuilding unchanged input against the same generation is byte-reproducible.
first_context_hash="$(sha256sum "$closure_dir/context.md" | awk '{print $1}')"
first_ledger_hash="$(sha256sum "$closure_dir/closure.tsv" | awk '{print $1}')"
"$HARNESS_HOME/bin/harness-build-context-closure" \
	"$TEST_ROOT/e2e.env" "$TEST_ROOT/context-assignment.md" >/dev/null
test "$(sha256sum "$closure_dir/context.md" | awk '{print $1}')" = "$first_context_hash"
test "$(sha256sum "$closure_dir/closure.tsv" | awk '{print $1}')" = "$first_ledger_hash"

# C++ overloads, namespace-qualified references, type-bearing declarations,
# complete implementation regions, and focused C++ tests remain closed.
cat > "$TEST_ROOT/context-cpp-assignment.md" <<'ASSIGNMENT'
Task-ID: context-cpp-test
Plan-Node: n02
Worker-Route: LUNA
Deliverable: Preserve overloaded scaling and typed accumulation behavior.
Acceptance-Evidence: context_calc_cpp_test exits successfully.
Focused-Validation: ctest --test-dir BUILD -R context_calc_cpp_test
Allowed-Scope: src/calc.cpp,include/calc.hpp,tests/test_calc_cpp.cpp
Context-Paths: src/calc.cpp,include/calc.hpp,tests/test_calc_cpp.cpp
Required-Symbols: context_scale,context_accumulate
ASSIGNMENT
cpp_output="$($HARNESS_HOME/bin/harness-build-context-closure \
	"$TEST_ROOT/e2e.env" "$TEST_ROOT/context-cpp-assignment.md")"
grep -Fq 'CONTEXT_CLOSURE status=READY task=context-cpp-test' <<< "$cpp_output"
cpp_dir="$TEST_ROOT/state/projects/scip-e2e/control/context-closures/scip-e2e-task-context-cpp-test"
test "$(awk -F '\t' 'NR>1 && $2=="DEFINITION" && $6=="context_scale" {n++} END {print n+0}' "$cpp_dir/closure.tsv")" = 2
grep -Fq 'double context_scale(double value, double factor)' "$cpp_dir/context.md"
grep -Fq 'state->total += value;' "$cpp_dir/context.md"
grep -Fq 'context_index::Accumulator state{2};' "$cpp_dir/context.md"
grep -Eq $'^build_targets\t2$' "$cpp_dir/quality.tsv"

# A generated header outside Git/SCIP is supplied through the hashed build-input
# graph rather than silently disappearing from the worker context.
cat > "$TEST_ROOT/context-generated-assignment.md" <<'ASSIGNMENT'
Task-ID: context-generated-test
Plan-Node: n03
Worker-Route: LUNA
Deliverable: Preserve the configured generated value.
Acceptance-Evidence: context_generated_value returns the configured value.
Focused-Validation: cmake --build BUILD --target context_generated
Allowed-Scope: src/generated.cpp
Context-Paths: src/generated.cpp
Required-Symbols: context_generated_value
ASSIGNMENT
generated_output="$($HARNESS_HOME/bin/harness-build-context-closure \
	"$TEST_ROOT/e2e.env" "$TEST_ROOT/context-generated-assignment.md")"
grep -Fq 'CONTEXT_CLOSURE status=READY task=context-generated-test' <<< "$generated_output"
generated_dir="$TEST_ROOT/state/projects/scip-e2e/control/context-closures/scip-e2e-task-context-generated-test"
grep -Eq $'^build_inputs\t2$' "$generated_dir/quality.tsv"
grep -Fq $'GENERATED_HEADER\tsrc/generated.cpp\tcontext_generated.hpp' "$generated_dir/build-inputs.tsv"
grep -Fq '#define CONTEXT_GENERATED_VALUE (CONTEXT_NESTED_BASE + 7)' "$generated_dir/context.md"
grep -Fq '#define CONTEXT_NESTED_BASE 10' "$generated_dir/context.md"

# Optional Joern projection supplies directional call, control/data-flow, and
# mutation evidence on demand without becoming the authoritative symbol source.
cp "$TEST_ROOT/e2e.env" "$TEST_ROOT/e2e-joern.env"
printf 'export PROJECT="scip-e2e-joern"\nexport HARNESS_JOERN_ENABLED="1"\nexport HARNESS_JOERN_SOURCE_ROOT="src"\n' >> "$TEST_ROOT/e2e-joern.env"
"$HARNESS_HOME/bin/harness-init" "$TEST_ROOT/e2e-joern.env" >/dev/null
"$HARNESS_HOME/bin/harness-index-repository" "$TEST_ROOT/e2e-joern.env" >/dev/null
joern_pointer="$TEST_ROOT/state/projects/scip-e2e-joern/control/repository-index.env"
joern_dir="$(awk -F= '$1=="generation_dir" {print $2}' "$joern_pointer")"
grep -Fqx 'joern_max_heap_mb=12288' "$joern_dir/manifest.env"
grep -Fqx 'joern_max_cpus=2' "$joern_dir/manifest.env"
grep -Eq '^joern_cpu_affinity=[0-9]+,[0-9]+$' "$joern_dir/manifest.env"
grep -Fqx 'joern_nice_level=10' "$joern_dir/manifest.env"
test "$(sqlite3 "$joern_dir/architecture.sqlite" "SELECT status FROM provider_runs WHERE provider='joern';")" = READY
test "$(sqlite3 "$joern_dir/architecture.sqlite" 'SELECT count(*) FROM control_flow_edges;')" -ge 1
test "$(sqlite3 "$joern_dir/architecture.sqlite" 'SELECT count(*) FROM data_flow_edges;')" -ge 1
test "$(sqlite3 "$joern_dir/architecture.sqlite" 'SELECT count(*) FROM mutation_edges;')" -ge 1
test "$(sqlite3 "$joern_dir/architecture.sqlite" 'SELECT count(*) FROM call_edges;')" -ge 1
test "$(sqlite3 "$joern_dir/architecture.sqlite" "SELECT count(*) FROM files WHERE repository_path='src/kernel.hip';")" = 1

# Luna-only on-demand mode keeps the immutable base index JVM-free, admits one
# bounded Joern overlay only for a flow-bearing leaf, and reuses that overlay by
# assignment/index/worktree digest.
cp "$TEST_ROOT/e2e.env" "$TEST_ROOT/e2e-joern-on-demand.env"
cat >> "$TEST_ROOT/e2e-joern-on-demand.env" <<'ENV'
export PROJECT="scip-e2e-joern-on-demand"
export HARNESS_MODEL_POLICY="luna_only"
export HARNESS_ESCALATION_POLICY="decompose"
export HARNESS_JOERN_ENABLED="1"
export HARNESS_JOERN_EXECUTION_MODE="on_demand"
export HARNESS_JOERN_SOURCE_ROOT="src"
ENV
"$HARNESS_HOME/bin/harness-init" "$TEST_ROOT/e2e-joern-on-demand.env" >/dev/null
"$HARNESS_HOME/bin/harness-index-repository" "$TEST_ROOT/e2e-joern-on-demand.env" >/dev/null
on_demand_pointer="$TEST_ROOT/state/projects/scip-e2e-joern-on-demand/control/repository-index.env"
on_demand_base="$(awk -F= '$1=="generation_dir" {print $2}' "$on_demand_pointer")"
grep -Fqx 'joern_execution_mode=on_demand' "$on_demand_base/manifest.env"
grep -Fqx 'joern_max_cpus=1' "$on_demand_base/manifest.env"
grep -Fqx 'joern_max_heap_mb=4096' "$on_demand_base/manifest.env"
test "$(sqlite3 "$on_demand_base/architecture.sqlite" "SELECT status FROM provider_runs WHERE provider='joern';")" = UNAVAILABLE
cat > "$TEST_ROOT/context-flow-assignment.md" <<'ASSIGNMENT'
Task-ID: context-flow-test
Plan-Node: n-flow
Worker-Route: LUNA
Leaf-Type: LOCAL_IMPLEMENTATION
Required-Dependency-Classes: D,F,V
Deliverable: Preserve the indexed mutation flow.
Acceptance-Evidence: context_add behavior remains validated.
Focused-Validation: ctest --test-dir BUILD -R context_calc_test
Allowed-Scope: src/calc.c
Context-Paths: src/calc.c
Required-Symbols: context_add
ASSIGNMENT
flow_output="$("$HARNESS_HOME/bin/harness-build-context-closure" \
	"$TEST_ROOT/e2e-joern-on-demand.env" "$TEST_ROOT/context-flow-assignment.md")"
grep -Fq 'CONTEXT_CLOSURE status=READY task=context-flow-test' <<< "$flow_output"
flow_overlay="$(find "$TEST_ROOT/state/projects/scip-e2e-joern-on-demand/control/flow-overlays" \
	-mindepth 1 -maxdepth 1 -type d ! -name '.*' | head -n 1)"
test -f "$flow_overlay/READY"
test "$(sqlite3 "$flow_overlay/architecture.sqlite" "SELECT status FROM provider_runs WHERE provider='joern';")" = READY
flow_overlay_digest="$(sha256sum "$flow_overlay/architecture.sqlite" | awk '{print $1}')"
"$HARNESS_HOME/bin/harness-build-context-closure" \
	"$TEST_ROOT/e2e-joern-on-demand.env" "$TEST_ROOT/context-flow-assignment.md" >/dev/null
test "$(sha256sum "$flow_overlay/architecture.sqlite" | awk '{print $1}')" = "$flow_overlay_digest"

# Normative architecture authority is selected by exact registered IDs and can
# add contract artifacts and public symbols to the structural seed set.
architecture_dir="$TEST_ROOT/state/projects/scip-e2e/control/architecture"
mkdir -p "$architecture_dir"
cat > "$architecture_dir/invariants.tsv" <<'TSV'
invariant_id	category	authority	severity	statement	scope	source_requirement	validation_kind	validation_ref	affected_nodes
INV-add	PUBLIC_API	SPECIFIED	CRITICAL	Addition remains compatible.	src/calc.c,include/calc.h	spec.md:1	COMMAND	ctest --test-dir BUILD	n01
TSV
cat > "$architecture_dir/decisions.tsv" <<'TSV'
decision_id	status	producer_node	problem	chosen_contract	affected_interfaces	supersedes	evidence
ADR-add	ACCEPTED	n00	Preserve the public addition seam.	Use the declared context_add interface.	context_add	-	include/calc.h
TSV
cat > "$architecture_dir/edges.tsv" <<'TSV'
edge_id	producer_node	consumer_node	contract_artifact	public_symbols	ownership_model	representation	versioning_rule	compatibility_validation	decision_ids	invariant_ids
EDGE-add	n00	n01	include/calc.h	context_add	caller-owned integers	C integer	compatible	ctest --test-dir BUILD	ADR-add	INV-add
TSV
cat > "$architecture_dir/node-bindings.tsv" <<'TSV'
node_id	invariant_ids	consumes_decisions	produces_decisions	edge_contracts	health_gates
n01	INV-add	ADR-add	-	EDGE-add	GATE-add
TSV
cat > "$architecture_dir/health-gates.tsv" <<'TSV'
gate_id	trigger_node	depends_on	validation	severity	invariant_ids	edge_ids
GATE-add	n01	n00	ctest --test-dir BUILD	CRITICAL	INV-add	EDGE-add
TSV
printf 'debt_id\tintroduced_by_task\tintroduced_by_commit\tcategory\taffected_invariants\tconsequence\tremediation_node\tseverity\texpires_at\tstatus\twaiver_authority\n' \
	> "$architecture_dir/debt.tsv"
printf 'decision_id\tstatus\ttask_id\tcommit\tevidence\trecorded_at\n' \
	> "$architecture_dir/decision-ledger.tsv"
printf 'gate_id\tstatus\ttask_id\tcommit\tevidence\trecorded_at\n' \
	> "$architecture_dir/health-ledger.tsv"
printf 'debt_id\tstatus\ttask_id\tcommit\tevidence\trecorded_at\n' \
	> "$architecture_dir/debt-ledger.tsv"
cp "$TEST_ROOT/e2e.env" "$TEST_ROOT/e2e-architecture.env"
printf 'export HARNESS_DECOMPOSITION_V2="1"\nexport HARNESS_ARCHITECTURE_GUARDS="1"\n' \
	>> "$TEST_ROOT/e2e-architecture.env"
sed -e 's/^Affected-Invariants:.*/Affected-Invariants: INV-add/' \
	-e 's/^Edge-Contracts:.*/Edge-Contracts: EDGE-add/' \
	"$TEST_ROOT/context-assignment.md" > "$TEST_ROOT/architecture-assignment.md"
cat >> "$TEST_ROOT/architecture-assignment.md" <<'ASSIGNMENT'
Consumed-Decisions: ADR-add
Produced-Decisions: -
Health-Gates: GATE-add
ASSIGNMENT
architecture_output="$($HARNESS_HOME/bin/harness-build-context-closure \
	"$TEST_ROOT/e2e-architecture.env" "$TEST_ROOT/architecture-assignment.md")"
grep -Fq 'CONTEXT_CLOSURE status=READY' <<< "$architecture_output"
grep -Eq $'^authority_records\t4$' "$closure_dir/quality.tsv"
grep -Eq $'^ownership_boundaries\t1$' "$closure_dir/quality.tsv"
grep -Fq $'EDGE-add\tn00\tn01\tcaller-owned integers' "$closure_dir/ownership-boundaries.tsv"
grep -Fq $'ARCHITECTURE_INVARIANT\tINV-add\t' "$closure_dir/authority.tsv"
grep -Fq $'ARCHITECTURE_DECISION\tADR-add\t' "$closure_dir/authority.tsv"
grep -Fq 'Addition remains compatible.' "$closure_dir/context.md"

# Derived maps never replace normative authority. Project-local projection,
# navigation benchmarks, scorecards, and redesign proposals remain reproducible.
architecture_index_output="$($HARNESS_HOME/bin/harness-architecture-index "$TEST_ROOT/e2e-architecture.env")"
architecture_index_dir="$(sed -n 's/^ARCHITECTURE_INDEX_READY generation=[^ ]* path=//p' <<< "$architecture_index_output")"
grep -Fq $'INVARIANT\tINV-add\tSPECIFIED' "$architecture_index_dir/normative-projection.tsv"
grep -Fq $'DECISION\tADR-add\tNORMATIVE' "$architecture_index_dir/normative-projection.tsv"
benchmark_output="$($HARNESS_HOME/bin/harness-architecture-benchmarks \
	"$TEST_ROOT/e2e-architecture.env" "$TEST_ROOT/repo/architecture-benchmarks.tsv")"
grep -Eq $'^context-add-definition\tcontext_add\tsrc/calc.c\tsrc/calc.c\t1\t1\t1\t' <<< "$benchmark_output"
scorecard_output="$($HARNESS_HOME/bin/harness-architecture-scorecard "$TEST_ROOT/e2e-architecture.env")"
grep -Fq $'benchmark_queries\t2' <<< "$scorecard_output"
test -s "$TEST_ROOT/state/projects/scip-e2e/control/architecture-scorecards/$(basename "$e2e_generation_dir")/rebuild-proposal.md"

# Required-mode admission returns nonzero before a worker when deterministic
# closure measurements exceed the route budget.
cp "$TEST_ROOT/e2e.env" "$TEST_ROOT/e2e-required.env"
printf 'export HARNESS_CONTEXT_CLOSURE_MODE="required"\nexport HARNESS_CONTEXT_CLOSURE_MAX_BYTES="512"\n' \
	>> "$TEST_ROOT/e2e-required.env"
set +e
"$HARNESS_HOME/bin/harness-evaluate-decomposition-context" "$TEST_ROOT/e2e-required.env" \
	"$TEST_ROOT/candidate-dag.tsv" "$TEST_ROOT/candidate-coverage.tsv" - \
	"$TEST_ROOT/context-admission-required" --enforce >/dev/null
required_status=$?
set -e
test "$required_status" = 3
grep -Eq $'^n01\tLUNA\tNEEDS_FURTHER_DECOMPOSITION\t' \
	"$TEST_ROOT/context-admission-required/admission.tsv"

sed 's/context_add/symbol_that_does_not_exist/g' "$TEST_ROOT/candidate-dag.tsv" > \
	"$TEST_ROOT/missing-candidate-dag.tsv"
set +e
"$HARNESS_HOME/bin/harness-evaluate-decomposition-context" "$TEST_ROOT/e2e-required.env" \
	"$TEST_ROOT/missing-candidate-dag.tsv" "$TEST_ROOT/candidate-coverage.tsv" - \
	"$TEST_ROOT/context-admission-missing" --enforce >/dev/null
missing_candidate_status=$?
set -e
test "$missing_candidate_status" = 3
grep -Fq $'n01\tINDEX_EVIDENCE_MISSING\tREFRESH_INDEX_OR_OVERLAY\tscip\tREQUIRED_SYMBOL\tsymbol_that_does_not_exist\tno exact SCIP or worktree-overlay definition' \
	"$TEST_ROOT/context-admission-missing/repair.tsv"

# Missing structural authority fails closed instead of accepting lexical recall.
sed 's/Required-Symbols: context_add/Required-Symbols: symbol_that_does_not_exist/' \
	"$TEST_ROOT/context-assignment.md" > "$TEST_ROOT/missing-assignment.md"
sed -i 's/Task-ID: context-add-test/Task-ID: missing-symbol-test/' \
	"$TEST_ROOT/missing-assignment.md"
missing_output="$($HARNESS_HOME/bin/harness-build-context-closure \
	"$TEST_ROOT/e2e.env" "$TEST_ROOT/missing-assignment.md")"
grep -Fq 'CONTEXT_CLOSURE status=INCOMPLETE task=missing-symbol-test' <<< "$missing_output"
missing_dir="$TEST_ROOT/state/projects/scip-e2e/control/context-closures/scip-e2e-task-missing-symbol-test"
grep -Fq $'REQUIRED_SYMBOL\tsymbol_that_does_not_exist\t' "$missing_dir/unresolved.tsv"
set +e
"$HARNESS_HOME/bin/harness-context-closure-check" \
	"$TEST_ROOT/e2e.env" missing-symbol-test >/dev/null
missing_check_status=$?
set -e
test "$missing_check_status" = 3

# A closure that exceeds a route budget is returned for further decomposition.
cp "$TEST_ROOT/e2e.env" "$TEST_ROOT/e2e-small-budget.env"
printf 'export HARNESS_CONTEXT_CLOSURE_MAX_BYTES="512"\n' >> "$TEST_ROOT/e2e-small-budget.env"
small_output="$($HARNESS_HOME/bin/harness-build-context-closure \
	"$TEST_ROOT/e2e-small-budget.env" "$TEST_ROOT/context-assignment.md")"
grep -Fq 'CONTEXT_CLOSURE status=NEEDS_FURTHER_DECOMPOSITION' <<< "$small_output"
grep -Eq $'^reasons\t.*context-byte-budget-exceeded' "$closure_dir/quality.tsv"

# A tracked overlay spans committed progress after the immutable indexed
# baseline as well as dirty tracked changes. Unchanged compile/build/provider
# fingerprints remain mandatory, while live source evidence is relocated from
# the full baseline-to-worktree delta without another SCIP/Joern build.
cp "$TEST_ROOT/e2e.env" "$TEST_ROOT/e2e-history-overlay.env"
printf 'export HARNESS_REPOSITORY_OVERLAY_MODE="tracked"\n' \
	>> "$TEST_ROOT/e2e-history-overlay.env"
sed -i 's/return left + right;/return left + right + 0;/' "$TEST_ROOT/repo/src/calc.c"
git -C "$TEST_ROOT/repo" add src/calc.c
git -C "$TEST_ROOT/repo" -c user.name=test -c user.email=test@example.invalid \
	commit -qm 'advance indexed source fixture'
history_output="$($HARNESS_HOME/bin/harness-build-context-closure \
	"$TEST_ROOT/e2e-history-overlay.env" "$TEST_ROOT/context-assignment.md")"
grep -Fq 'CONTEXT_CLOSURE status=READY' <<< "$history_output"
grep -Fq 'return left + right + 0;' "$closure_dir/context.md"
grep -Fq $'src/calc.c\tMODIFIED\t' \
	"$TEST_ROOT/state/projects/scip-e2e/control/repository-worktree-overlay.tsv"

# Consumers fail closed when the committed index no longer describes the
# tracked worktree.  Restore the fixture without rewriting Git history.
cp "$TEST_ROOT/repo/src/calc.c" "$TEST_ROOT/calc.c.saved"
printf '\n/* stale-index fixture */\n' >> "$TEST_ROOT/repo/src/calc.c"
if "$HARNESS_HOME/bin/harness-query-architecture" "$TEST_ROOT/e2e.env" context_add \
	> "$TEST_ROOT/stale-query.out" 2>&1; then
	printf 'architecture query accepted a stale repository index\n' >&2
	exit 1
fi
grep -Fq 'tracked-worktree-changed' "$TEST_ROOT/stale-query.out"
mv "$TEST_ROOT/calc.c.saved" "$TEST_ROOT/repo/src/calc.c"

# A malformed protobuf must not leave a partially imported transaction.
printf 'not-a-scip-index\n' > "$TEST_ROOT/malformed.scip"
malformed_database="$TEST_ROOT/malformed.sqlite"
sqlite3 "$malformed_database" < "$HARNESS_HOME/formats/repository-index-schema.sql" >/dev/null
sqlite3 "$malformed_database" \
	"INSERT INTO index_generations VALUES('malformed-generation','fixture-repository','fixture-revision','fixture-compdb','fixture-generated-inputs','fixture-scip-clang','fixture-scip','fixture-importer','fixture-build-importer','fixture-schema','READY','2026-08-16T00:00:00Z');"
if "$importer" --index "$TEST_ROOT/malformed.scip" --database "$malformed_database" \
	--generation malformed-generation --repository "$SCRIPT_DIR/fixtures/context-index-c" \
	--report "$TEST_ROOT/malformed.tsv" > "$TEST_ROOT/malformed.out" 2>&1; then
	printf 'malformed SCIP payload was accepted\n' >&2
	exit 1
fi
test "$(sqlite3 "$malformed_database" 'SELECT count(*) FROM files;')" = 0

printf 'scip importer integration tests passed\n'
