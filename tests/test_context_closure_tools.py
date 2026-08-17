#!/usr/bin/env python3

import csv
import hashlib
import os
from pathlib import Path
import sqlite3
import subprocess
import tempfile
import unittest
from unittest.mock import patch
from types import SimpleNamespace


ROOT = Path(__file__).resolve().parents[1]
import sys
sys.path.insert(0, str(ROOT / "tools"))
from context_closure import build_closure
from evaluate_decomposition_context import evaluate as evaluate_decomposition_context


class ContextClosureToolsTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="context-closure-tools.")
        self.root = Path(self.temporary.name)
        self.repository = self.root / "repo"
        self.repository.mkdir()
        subprocess.run(["git", "init", "-q", str(self.repository)], check=True)
        (self.repository / "calc.c").write_text("int add(int a, int b) { return a + b; }\n", encoding="utf-8")
        (self.repository / "calc.h").write_text("int add(int a, int b);\n", encoding="utf-8")
        (self.repository / "src").mkdir()
        (self.repository / "src" / "other.c").write_text("int other(void) { return 1; }\n", encoding="utf-8")
        subprocess.run(["git", "-C", str(self.repository), "add", "."], check=True)
        subprocess.run(["git", "-C", str(self.repository), "-c", "user.name=test", "-c",
                        "user.email=test@example.invalid", "commit", "-qm", "seed"], check=True)
        self.database = self.root / "architecture.sqlite"
        subprocess.run(["sqlite3", str(self.database)], input=(ROOT / "formats/repository-index-schema.sql").read_bytes(), check=True)
        connection = sqlite3.connect(self.database)
        connection.execute("INSERT INTO index_generations VALUES(?,?,?,?,?,?,?,?,?,?,?,?)",
                           ("g", "r", "rev", "c", "i", "sc", "s", "imp", "bi", "schema", "READY", "now"))
        connection.execute("INSERT INTO build_configurations VALUES('c','g','compile_commands.json','c',NULL,NULL,'{}')")
        connection.execute("INSERT INTO files VALUES(1,'g','calc.c','c',NULL,1,0)")
        connection.execute("INSERT INTO source_regions VALUES(1,1,'symbol_definition','add',1,0,1,40,NULL,'scip-clang')")
        connection.execute("INSERT INTO symbols VALUES('sym','g','add','Function','c','-','scip-clang')")
        connection.execute("INSERT INTO symbol_definitions VALUES('sym',1,'definition','scip-clang')")
        connection.execute("INSERT INTO provider_runs VALUES('joern','g','test','disabled','UNAVAILABLE',NULL,'now')")
        connection.commit()
        connection.close()

    def tearDown(self):
        self.temporary.cleanup()

    def closure(self, extra: str = "", omissions: Path | None = None,
                overlay: Path | None = None, max_bytes: int = 32768,
                luna_only: bool = False, context_paths: str = "calc.c",
                required_symbols: str = "add",
                allowed_scope: str = "calc.c",
                decisions: Path | None = None) -> tuple[str, Path]:
        assignment = self.root / "assignment.md"
        assignment.write_text(
            f"Task-ID: t1\nPlan-Node: n1\nWorker-Route: LUNA\nAllowed-Scope: {allowed_scope}\n"
            f"Context-Paths: {context_paths}\nRequired-Symbols: {required_symbols}\n" + extra,
            encoding="utf-8")
        output = self.root / ("closure-" + str(len(list(self.root.glob("closure-*")))))
        arguments = SimpleNamespace(
            assignment=str(assignment), database=str(self.database), repository=str(self.repository),
            generation="g", output=str(output), max_bytes=max_bytes, max_symbols=32, max_modules=4,
            max_ownership_boundaries=2, max_direct_relationships=8, max_tests=4,
            max_build_targets=4, max_tokens=10000, obligations_file=None, relations_file=None,
            invariants_file=None, decisions_file=str(decisions) if decisions else None,
            edges_file=None, health_gates_file=None,
            node_bindings_file=None, omissions_file=str(omissions) if omissions else None,
            overlay_file=str(overlay) if overlay else None, luna_only=luna_only)
        return build_closure(arguments), output

    def test_decomposition_aggregate_keeps_provider_only_graph_cut_repair(self):
        dag = self.root / "dag.tsv"
        dag.write_text(
            "node_id\tparent_id\tdepends_on\tdeliverable\tacceptance_evidence\t"
            "focused_validation\tallowed_paths\trequired_symbols\tleaf_type\t"
            "complexity_class\tworker_route\n"
            "n1\t-\t-\tBounded work.\tFocused evidence.\ttrue\tcalc.c\tadd\t"
            "LOCAL_IMPLEMENTATION\tLOW\tLUNA\n",
            encoding="utf-8",
        )
        output = self.root / "admission"

        def fake_build(arguments):
            node = Path(arguments.output)
            (node / "quality.tsv").write_text(
                "metric\tvalue\nstatus\tNEEDS_FURTHER_DECOMPOSITION\n"
                "context_bytes\t40960\nestimated_tokens\t10240\n"
                "reasons\tcontext-byte-budget-exceeded\n",
                encoding="utf-8",
            )
            (node / "suggested-cuts.tsv").write_text(
                "cut_id\tseam_kind\tcohesive_key\trequired_symbols\tallowed_paths\t"
                "acceptance_hint\troute_hint\testimated_source_bytes\trationale\n",
                encoding="utf-8",
            )
            (node / "repair.tsv").write_text(
                "condition\trepair_action\tprovider\tevidence_kind\tidentifier\treason\n"
                "CLOSURE_BUDGET_EXCEEDED\tGRAFT_GRAPH_CUTS\tdecomposition-compiler\t"
                "-\t-\tcontext-byte-budget-exceeded\n",
                encoding="utf-8",
            )
            return "NEEDS_FURTHER_DECOMPOSITION"

        arguments = SimpleNamespace(
            dag=str(dag), coverage=None, architecture=None, predictions=None,
            database=str(self.database), repository=str(self.repository), generation="g",
            output=str(output), max_bytes=32768, max_symbols=32, max_modules=4,
            max_ownership_boundaries=2, max_direct_relationships=8, max_tests=4,
            max_build_targets=4, max_tokens=10000, obligations_file=None,
            relations_file=None, omissions_file=None, enforce=True,
        )
        with patch("evaluate_decomposition_context.build_closure", side_effect=fake_build):
            self.assertEqual(3, evaluate_decomposition_context(arguments))
        aggregate = (output / "repair.tsv").read_text(encoding="utf-8")
        self.assertIn(
            "n1\tCLOSURE_BUDGET_EXCEEDED\tGRAFT_GRAPH_CUTS\t"
            "decomposition-compiler\t-\t-\tcontext-byte-budget-exceeded",
            aggregate,
        )

    def test_luna_only_budget_repair_compiles_deterministic_child_candidates(self):
        status, output = self.closure(max_bytes=32, luna_only=True)
        self.assertEqual("NEEDS_FURTHER_DECOMPOSITION", status)
        manifest = (output / "manifest.env").read_text()
        self.assertIn("condition=CLOSURE_BUDGET_EXCEEDED", manifest)
        self.assertIn("repair_action=GRAFT_GRAPH_CUTS", manifest)
        self.assertIn("semantic_split_required=1", manifest)
        cuts = (output / "suggested-cuts.tsv").read_text()
        self.assertIn("\tDECOMPOSE\t", cuts)
        self.assertNotIn("TERRA", cuts)
        children = (output / "repair-children.tsv").read_text()
        self.assertIn("CCR-", children)
        self.assertIn("\tcalc.c\tcalc.c\tadd\t", children)

    def test_missing_evidence_with_multiple_over_budget_seams_prefers_graph_cut(self):
        connection = sqlite3.connect(self.database)
        connection.execute("INSERT INTO files VALUES(2,'g','src/other.c','c',NULL,1,0)")
        connection.execute(
            "INSERT INTO source_regions VALUES(2,2,'symbol_definition','other',1,0,1,40,NULL,'scip-clang')")
        connection.execute(
            "INSERT INTO symbols VALUES('other-sym','g','other','Function','c','-','scip-clang')")
        connection.execute(
            "INSERT INTO symbol_definitions VALUES('other-sym',2,'definition','scip-clang')")
        connection.commit()
        connection.close()

        status, output = self.closure(
            max_bytes=32, luna_only=True,
            context_paths="calc.c,src/other.c",
            required_symbols="add,other,missing",
            allowed_scope="calc.c,src/other.c")

        self.assertEqual("INCOMPLETE", status)
        manifest = (output / "manifest.env").read_text()
        self.assertIn("reasons=unresolved-required-evidence,context-byte-budget-exceeded", manifest)
        self.assertIn("condition=CLOSURE_BUDGET_EXCEEDED", manifest)
        self.assertIn("repair_action=GRAFT_GRAPH_CUTS", manifest)
        self.assertIn("repair_provider=decomposition-compiler", manifest)
        self.assertIn("semantic_split_required=1", manifest)
        self.assertIn("repair_candidate_children=2", manifest)
        children = (output / "repair-children.tsv").read_text()
        self.assertIn("\tcalc.c\tcalc.c\tadd\t", children)
        self.assertIn("\tsrc/other.c\tsrc/other.c\tother\t", children)

    def test_repair_children_never_promote_read_only_context_to_write_scope(self):
        connection = sqlite3.connect(self.database)
        connection.execute("INSERT INTO files VALUES(2,'g','calc.h','c',NULL,1,0)")
        connection.commit()
        connection.close()

        _, output = self.closure(
            max_bytes=32, luna_only=True,
            context_paths="calc.c,calc.h", allowed_scope="calc.c")

        with (output / "repair-children.tsv").open(encoding="utf-8", newline="") as stream:
            children = list(csv.DictReader(stream, delimiter="\t"))
        self.assertTrue(children)
        self.assertEqual({"calc.c"}, {child["allowed_paths"] for child in children})
        self.assertEqual({"calc.c"}, {child["context_paths"] for child in children})
        self.assertNotIn("calc.h", {child["allowed_paths"] for child in children})

    def test_discovered_test_evidence_is_capped_before_capsule_rendering(self):
        connection = sqlite3.connect(self.database)
        for index in range(6):
            test_id = f"test-{index}"
            connection.execute(
                "INSERT INTO tests VALUES(?,?,?,?,?,?,?,?)",
                (test_id, "g", test_id, 1, 1, "calc-tests", test_id, "scip-clang"))
            connection.execute(
                "INSERT INTO test_symbol_edges VALUES(?,?,?,?)",
                (test_id, "sym", "COVERS", "scip-clang"))
        connection.commit()
        connection.close()

        _, output = self.closure()

        quality = (output / "quality.tsv").read_text()
        self.assertIn("tests\t4\n", quality)
        self.assertIn("bounded_test_candidates_omitted\t2\n", quality)
        context = (output / "context.md").read_text()
        self.assertIn("test-3", context)
        self.assertNotIn("test-4", context)
        self.assertNotIn("test-budget-exceeded", (output / "manifest.env").read_text())

    def test_bounded_supporting_call_fanout_does_not_force_decomposition(self):
        connection = sqlite3.connect(self.database)
        for index in range(9):
            symbol_id = f"callee-{index}"
            connection.execute(
                "INSERT INTO symbols VALUES(?, 'g', ?, 'Function', 'c', '-', 'scip-clang')",
                (symbol_id, symbol_id))
            connection.execute(
                "INSERT INTO symbol_definitions VALUES(?, 1, 'definition', 'scip-clang')",
                (symbol_id,))
            connection.execute(
                "INSERT INTO call_edges VALUES('sym', ?, 1, 'scip-clang', 'AUTHORITATIVE')",
                (symbol_id,))
        connection.commit()
        connection.close()

        status, output = self.closure()

        self.assertEqual("READY", status)
        self.assertIn("\tcall-fanout\t", (output / "graph-cut.tsv").read_text())
        quality = (output / "quality.tsv").read_text()
        self.assertIn("graph_cuts\t1\n", quality)
        self.assertIn("blocking_graph_cuts\t0\n", quality)
        self.assertIn("informational_graph_cuts\t1\n", quality)
        self.assertNotIn("structural-graph-cut", (output / "manifest.env").read_text())

    def test_ambiguous_display_name_prefers_definition_inside_declared_boundary(self):
        connection = sqlite3.connect(self.database)
        connection.execute("INSERT INTO files VALUES(2,'g','src/other.c','c',NULL,1,0)")
        connection.execute(
            "INSERT INTO source_regions VALUES(2,2,'symbol_definition','add',1,0,1,40,NULL,'scip-clang')")
        connection.execute(
            "INSERT INTO symbols VALUES('other-add','g','add','Function','c','-','scip-clang')")
        connection.execute(
            "INSERT INTO symbol_definitions VALUES('other-add',2,'definition','scip-clang')")
        connection.commit()
        connection.close()

        status, output = self.closure()

        self.assertEqual("READY", status)
        closure = (output / "closure.tsv").read_text()
        self.assertIn("\tcalc.c\t", closure)
        self.assertNotIn("\tsrc/other.c\t", closure)
        self.assertIn("modules\t1\n", (output / "quality.tsv").read_text())

    def test_header_boundary_prefers_exact_declaration_over_external_definitions(self):
        self.repository.joinpath("calc.h").write_text(
            "\n".join(["/* context */"] * 16 +
                      ["/* preserves the public addition contract */", "int add(int a, int b);"] +
                      ["/* trailing context */"] * 4) + "\n",
            encoding="utf-8")
        connection = sqlite3.connect(self.database)
        connection.execute("INSERT INTO files VALUES(2,'g','calc.h','c',NULL,1,0)")
        connection.execute(
            "INSERT INTO source_regions VALUES(2,2,'reference','add',18,0,18,20,NULL,'scip-clang')")
        connection.execute(
            "INSERT INTO symbol_references VALUES('sym',2,'declaration','scip-clang')")
        connection.commit()
        connection.close()

        status, output = self.closure(
            extra="Required-Dependency-Classes: D,I,V\n",
            context_paths="calc.h", allowed_scope="calc.h")

        self.assertEqual("READY", status)
        closure = (output / "closure.tsv").read_text()
        self.assertIn("SCOPED_DECLARATION\tcalc.h", closure)
        self.assertNotIn("DEFINITION\tcalc.c", closure)
        self.assertIn("modules\t1\n", (output / "quality.tsv").read_text())
        self.assertIn("preserves the public addition contract",
                      (output / "context.md").read_text())

    def test_scoped_symbol_references_embed_one_stable_occurrence(self):
        self.repository.joinpath("include").mkdir()
        self.repository.joinpath("include", "calc.h").write_text(
            "int first(void) { return add(1, 2); }\n"
            "int second(void) { return add(3, 4); }\n"
            "int third(void) { return add(5, 6); }\n",
            encoding="utf-8")
        connection = sqlite3.connect(self.database)
        connection.execute("INSERT INTO files VALUES(2,'g','include/calc.h','c',NULL,1,0)")
        for region_id, line in enumerate((1, 2, 3), start=2):
            connection.execute(
                "INSERT INTO source_regions VALUES(?,?, 'reference','add',?,0,?,40,NULL,'scip-clang')",
                (region_id, 2, line, line))
            connection.execute(
                "INSERT INTO symbol_references VALUES('sym',?,'reference','scip-clang')",
                (region_id,))
        connection.commit()
        connection.close()

        status, output = self.closure(
            extra="Required-Dependency-Classes: D,I,V\n",
            context_paths="include/calc.h", allowed_scope="include/calc.h")

        self.assertEqual("READY", status)
        closure_rows = (output / "closure.tsv").read_text().splitlines()
        scoped_rows = [row for row in closure_rows if "\tSCOPED_DECLARATION\tinclude/calc.h\t" in row]
        self.assertEqual(1, len(scoped_rows))
        interface_rows = [row for row in closure_rows if "\tINTERFACE_REFERENCE\tinclude/calc.h\t" in row]
        self.assertEqual(1, len(interface_rows))
        context = (output / "context.md").read_text()
        self.assertEqual(1, context.count("### SCOPED_DECLARATION:"))
        self.assertEqual(1, context.count("### INTERFACE_REFERENCE:"))

    def test_pure_missing_evidence_still_requests_provider_refresh(self):
        status, output = self.closure(required_symbols="missing")

        self.assertEqual("INCOMPLETE", status)
        manifest = (output / "manifest.env").read_text()
        self.assertIn("condition=INDEX_EVIDENCE_MISSING", manifest)
        self.assertIn("repair_action=REFRESH_INDEX_OR_OVERLAY", manifest)
        self.assertIn("repair_provider=scip", manifest)
        self.assertIn("semantic_split_required=0", manifest)

    def test_declared_context_path_supplies_symbol_scip_omitted(self):
        self.repository.joinpath("fixture.c").write_text(
            "static const char *semantic_gpu_architecture = \"matched\";\n",
            encoding="utf-8")

        status, output = self.closure(
            context_paths="fixture.c", allowed_scope="fixture.c",
            required_symbols="semantic_gpu_architecture")

        self.assertEqual("READY", status)
        self.assertNotIn("REQUIRED_SYMBOL\tsemantic_gpu_architecture",
                         (output / "unresolved.tsv").read_text())
        closure = (output / "closure.tsv").read_text()
        self.assertIn("\tBOUNDED_SOURCE_EVIDENCE\tfixture.c\t", closure)
        self.assertIn("\tdeclared-context-path\n", closure)
        self.assertIn("semantic_gpu_architecture = \"matched\"",
                      (output / "context.md").read_text())

    def test_unused_context_directory_is_a_boundary_not_missing_evidence(self):
        self.repository.joinpath("tests").mkdir()
        self.repository.joinpath("tests", "unrelated.c").write_text(
            "int unrelated(void) { return 0; }\n", encoding="utf-8")

        status, output = self.closure(
            context_paths="calc.c,tests", allowed_scope="calc.c",
            required_symbols="add")

        self.assertEqual("READY", status)
        self.assertNotIn("CONTEXT_PATH\ttests", (output / "unresolved.tsv").read_text())
        self.assertNotIn("tests/unrelated.c", (output / "closure.tsv").read_text())

    def test_context_file_symbol_selector_embeds_bounded_window(self):
        status, output = self.closure(
            context_paths="calc.c#add", allowed_scope="calc.c",
            required_symbols="add")

        self.assertEqual("READY", status)
        self.assertNotIn("CONTEXT_PATH\tcalc.c#add", (output / "unresolved.tsv").read_text())
        closure = (output / "closure.tsv").read_text()
        self.assertIn("\tBOUNDED_SOURCE_EVIDENCE\tcalc.c\t", closure)
        self.assertIn("\tdeclared-context-selector\n", closure)

    def test_required_symbol_build_target_alias_uses_indexed_validation_boundary(self):
        connection = sqlite3.connect(self.database)
        connection.execute(
            "INSERT INTO build_targets VALUES('target-calc','g','calc-tool','EXECUTABLE','Makefile','make')")
        connection.commit()
        connection.close()

        status, output = self.closure(required_symbols="calc-tool")

        self.assertEqual("READY", status)
        self.assertNotIn("REQUIRED_SYMBOL\tcalc-tool", (output / "unresolved.tsv").read_text())
        self.assertIn("\tcalc-tool\tEXECUTABLE\tMakefile\t", (output / "build-targets.tsv").read_text())
        self.assertIn("`calc-tool` (EXECUTABLE)", (output / "context.md").read_text())

    def test_architecture_interface_inventory_remains_compiled_authority(self):
        decisions = self.root / "decisions.tsv"
        decisions.write_text(
            "decision_id\tstate\taffected_interfaces\tevidence\n"
            "ADR-PATH\tACCEPTED\tcalc.h\toperator-worktree:design.md\n",
            encoding="utf-8")

        status, output = self.closure(
            extra="Consumed-Decisions: ADR-PATH\n",
            required_symbols="-", decisions=decisions)

        self.assertEqual("READY", status)
        self.assertNotIn("REQUIRED_SYMBOL\tcalc.h", (output / "unresolved.tsv").read_text())
        self.assertNotIn("DECLARED_CONTEXT\tcalc.h", (output / "closure.tsv").read_text())
        self.assertIn("ARCHITECTURE_DECISION\tADR-PATH", (output / "authority.tsv").read_text())

    def test_tracked_worktree_overlay_relocates_live_symbol_evidence(self):
        live_source = "\n".join(["/* inserted */"] * 24 +
                                ["int add(int a, int b) { return a + b + 1; }"]) + "\n"
        (self.repository / "calc.c").write_text(live_source, encoding="utf-8")
        digest = hashlib.sha256(live_source.encode()).hexdigest()
        overlay = self.root / "overlay.tsv"
        overlay.write_text(
            "repository_path\tstatus\tcontent_sha256\tcontent_bytes\n"
            f"calc.c\tMODIFIED\t{digest}\t{len(live_source.encode())}\n",
            encoding="utf-8")
        status, output = self.closure(overlay=overlay)
        self.assertEqual("READY", status)
        context = (output / "context.md").read_text()
        self.assertIn("return a + b + 1", context)
        self.assertIn("Worktree-Overlay-Paths: 1", context)
        self.assertIn("worktree-overlay", (output / "closure.tsv").read_text())
        manifest = (output / "manifest.env").read_text()
        self.assertIn("worktree_overlay_paths=1", manifest)

    def test_conflicting_configuration_fails_closed(self):
        connection = sqlite3.connect(self.database)
        connection.execute("INSERT INTO build_configurations VALUES('other','g','other.json','other',NULL,NULL,'{}')")
        connection.commit()
        connection.close()
        status, output = self.closure()
        self.assertEqual("INCOMPLETE", status)
        self.assertIn("multiple indexed configurations", (output / "unresolved.tsv").read_text())
        manifest = (output / "manifest.env").read_text()
        self.assertIn("condition=INDEX_EVIDENCE_MISSING", manifest)
        self.assertIn("repair_action=REFRESH_INDEX_OR_OVERLAY", manifest)
        self.assertIn("repair_provider=build-index", manifest)
        self.assertIn("BUILD_CONFIGURATION", (output / "repair.tsv").read_text())

    def test_requested_flow_without_joern_fails_closed(self):
        status, output = self.closure("Required-Dependency-Classes: D,F\n")
        self.assertEqual("INCOMPLETE", status)
        self.assertIn("Joern flow evidence was requested", (output / "unresolved.tsv").read_text())
        self.assertIn("repair_provider=joern", (output / "manifest.env").read_text())

    def test_requested_flow_embeds_bounded_joern_evidence(self):
        connection = sqlite3.connect(self.database)
        connection.execute("UPDATE provider_runs SET status='READY' WHERE provider='joern'")
        connection.execute("INSERT INTO source_regions VALUES(2,1,'joern_node','RETURN',1,0,1,1,NULL,'joern')")
        connection.execute("INSERT INTO source_regions VALUES(3,1,'joern_node','CALL',1,2,1,3,NULL,'joern')")
        connection.execute("INSERT INTO control_flow_edges VALUES(2,3,'CFG','joern')")
        connection.execute("INSERT INTO data_flow_edges VALUES(2,3,'a','REACHING_DEF','joern')")
        connection.execute("INSERT INTO mutation_edges VALUES('sym','sym','a + b',2,'joern','DERIVED')")
        connection.commit()
        connection.close()
        status, output = self.closure("Required-Dependency-Classes: D,F\n")
        self.assertEqual("READY", status)
        closure = (output / "closure.tsv").read_text()
        self.assertIn("CONTROL_FLOW\tcalc.c", closure)
        self.assertIn("DATA_FLOW\tcalc.c", closure)
        self.assertIn("MUTATION\tcalc.c", closure)
        quality = (output / "quality.tsv").read_text()
        self.assertIn("joern_flow_relationships\t2", quality)
        self.assertIn("joern_mutations\t1", quality)

    def test_documentation_leaf_does_not_expand_behavior_or_decision_inventory(self):
        connection = sqlite3.connect(self.database)
        connection.execute("INSERT INTO files VALUES(2,'g','calc.h','c',NULL,1,0)")
        connection.execute("INSERT INTO source_regions VALUES(2,2,'reference','add',1,0,1,20,NULL,'scip-clang')")
        connection.execute("INSERT INTO symbol_references VALUES('sym',2,'reference','scip-clang')")
        connection.execute("INSERT INTO symbols VALUES('other-sym','g','other','Function','c','-','scip-clang')")
        connection.execute("INSERT INTO files VALUES(3,'g','src/other.c','c',NULL,1,0)")
        connection.execute("INSERT INTO source_regions VALUES(3,3,'symbol_definition','other',1,0,1,40,NULL,'scip-clang')")
        connection.execute("INSERT INTO symbol_definitions VALUES('other-sym',3,'definition','scip-clang')")
        connection.execute("INSERT INTO call_edges VALUES('sym','other-sym',1,'scip-clang','AUTHORITATIVE')")
        connection.commit()
        connection.close()
        registry = self.root / "registry-docs"
        registry.mkdir()
        decisions = registry / "decisions.tsv"
        decisions.write_text(
            "decision_id\tstatus\tproducer_node\tproblem\tchosen_contract\taffected_interfaces\tsupersedes\tevidence\n"
            "ADR-add\tACCEPTED\tn1\tAPI\tKeep add public.\tadd,other\t-\tcalc.h\n",
            encoding="utf-8")
        assignment = self.root / "assignment-docs.md"
        assignment.write_text(
            "Task-ID: t-docs\nPlan-Node: n1\nWorker-Route: LUNA\nLeaf-Type: DOCUMENTATION\n"
            "Allowed-Scope: calc.h\nContext-Paths: calc.h\nRequired-Symbols: add\n"
            "Consumed-Decisions: ADR-add\n", encoding="utf-8")
        output = self.root / "closure-docs"
        arguments = SimpleNamespace(
            assignment=str(assignment), database=str(self.database), repository=str(self.repository),
            generation="g", output=str(output), max_bytes=32768, max_symbols=32, max_modules=4,
            max_ownership_boundaries=2, max_direct_relationships=8, max_tests=4,
            max_build_targets=4, max_tokens=10000, obligations_file=None, relations_file=None,
            invariants_file=None, decisions_file=str(decisions), edges_file=None,
            health_gates_file=None, node_bindings_file=None, omissions_file=None)
        self.assertEqual("READY", build_closure(arguments))
        closure = (output / "closure.tsv").read_text()
        self.assertIn("SCOPED_DECLARATION\tcalc.h", closure)
        self.assertNotIn("DEFINITION\tcalc.c", closure)
        self.assertNotIn("CALLEE", closure)
        self.assertNotIn("\tother\t", closure)
        self.assertIn("Required-Dependency-Classes: D,I,V", (output / "context.md").read_text())

    def test_descriptive_architecture_scope_is_not_a_missing_path(self):
        registry = self.root / "registry-descriptive"
        registry.mkdir()
        invariants = registry / "invariants.tsv"
        invariants.write_text(
            "invariant_id\tcategory\tauthority\tseverity\tstatement\tscope\tsource_requirement\tvalidation_kind\tvalidation_ref\taffected_nodes\n"
            "INV-add\tCONTRACT\tSPECIFICATION\tHIGH\tAddition remains public.\tQuery plan wire ABI\tREQ-1\tCOMMAND\tcc -c calc.c\tn1\n",
            encoding="utf-8")
        assignment = self.root / "assignment.md"
        assignment.write_text(
            "Task-ID: t1\nPlan-Node: n1\nWorker-Route: LUNA\nAllowed-Scope: calc.c\n"
            "Context-Paths: calc.c\nRequired-Symbols: add\nAffected-Invariants: INV-add\n",
            encoding="utf-8")
        output = self.root / "closure-descriptive-scope"
        arguments = SimpleNamespace(
            assignment=str(assignment), database=str(self.database), repository=str(self.repository),
            generation="g", output=str(output), max_bytes=32768, max_symbols=32, max_modules=4,
            max_ownership_boundaries=2, max_direct_relationships=8, max_tests=4,
            max_build_targets=4, max_tokens=10000, obligations_file=None, relations_file=None,
            invariants_file=str(invariants), decisions_file=None, edges_file=None,
            health_gates_file=None, node_bindings_file=None, omissions_file=None)
        self.assertEqual("READY", build_closure(arguments))
        self.assertNotIn("Query plan wire ABI", (output / "unresolved.tsv").read_text())

    def test_directory_context_requires_exact_structural_seed(self):
        assignment = self.root / "assignment.md"
        assignment.write_text(
            "Task-ID: t-dir\nPlan-Node: n1\nWorker-Route: LUNA\nAllowed-Scope: src\n"
            "Context-Paths: src\nRequired-Symbols: -\n", encoding="utf-8")
        output = self.root / "closure-directory"
        arguments = SimpleNamespace(
            assignment=str(assignment), database=str(self.database), repository=str(self.repository),
            generation="g", output=str(output), max_bytes=32768, max_symbols=32, max_modules=4,
            max_ownership_boundaries=2, max_direct_relationships=8, max_tests=4,
            max_build_targets=4, max_tokens=10000, obligations_file=None, relations_file=None,
            invariants_file=None, decisions_file=None, edges_file=None, health_gates_file=None,
            node_bindings_file=None, omissions_file=None)
        self.assertEqual("INCOMPLETE", build_closure(arguments))
        self.assertIn("directory path has no exact required symbol", (output / "unresolved.tsv").read_text())
        self.assertIn("repair_action=REFRESH_INDEX_OR_OVERLAY", (output / "manifest.env").read_text())

    def test_external_sdk_input_is_hashed_but_not_embedded(self):
        external = self.root / "sdk.h"
        external.write_text("SDK_INTERNAL " + ("x" * 40000), encoding="utf-8")
        connection = sqlite3.connect(self.database)
        connection.execute("INSERT INTO build_targets VALUES('target','g','calc','CMAKE_COMPILE_TARGET','CMakeLists.txt','test')")
        connection.execute("INSERT INTO build_target_files VALUES('target',1,'c','COMPILE_SOURCE','calc.o','test')")
        connection.execute("INSERT INTO build_inputs VALUES('input','g',?,'hash','EXTERNAL_HEADER','test')", (str(external),))
        connection.execute("INSERT INTO build_target_inputs VALUES('target','input','calc.c','sdk.h','calc.c','test')")
        connection.commit()
        connection.close()
        status, output = self.closure()
        self.assertEqual("READY", status)
        context = (output / "context.md").read_text()
        self.assertIn("External prerequisite `sdk.h`", context)
        self.assertNotIn("SDK_INTERNAL", context)
        self.assertIn("EXTERNAL_HEADER", (output / "build-inputs.tsv").read_text())

    def test_reviewed_systematic_omission_routes_to_remediation(self):
        omissions = self.root / "omissions.tsv"
        omissions.write_text("repository_path\tmissing_episodes\taction\n"
                             "calc.c\t3\tINDEX_OR_CLOSURE_REMEDIATION\n", encoding="utf-8")
        status, output = self.closure(omissions=omissions)
        self.assertEqual("INCOMPLETE", status)
        self.assertIn("SYSTEMATIC_CONTEXT_OMISSION\tcalc.c", (output / "unresolved.tsv").read_text())
        self.assertIn("systematic_omissions\t1", (output / "quality.tsv").read_text())

    def test_patch_scope_and_binary_guards(self):
        response = self.root / "response.md"
        response.write_text("""```diff
diff --git a/calc.c b/calc.c
index a7ca668..95e02df 100644
--- a/calc.c
+++ b/calc.c
@@ -1 +1 @@
-int add(int a, int b) { return a + b; }
+int add(int a, int b) { return (a + b); }
```
""", encoding="utf-8")
        patch = self.root / "proposal.patch"
        paths = self.root / "paths"
        subprocess.run(["python3", str(ROOT / "tools/apply_worker_patch.py"),
                        "--repository", str(self.repository), "--response", str(response),
                        "--allowed-scope", "calc.c", "--patch-output", str(patch),
                        "--paths-output", str(paths), "--max-files", "1"], check=True)
        self.assertIn("return (a + b)", (self.repository / "calc.c").read_text())
        self.assertEqual("calc.c\n", paths.read_text())

        subprocess.run(["git", "-C", str(self.repository), "restore", "calc.c"], check=True)
        response.write_text("""```diff
diff --git a/calc.h b/calc.h
index 9f799be..0af6d43 100644
--- a/calc.h
+++ b/calc.h
@@ -1 +1 @@
-int add(int a, int b);
+int add(long a, long b);
```
""", encoding="utf-8")
        rejected = subprocess.run(["python3", str(ROOT / "tools/apply_worker_patch.py"),
                                   "--repository", str(self.repository), "--response", str(response),
                                   "--allowed-scope", "calc.c", "--patch-output", str(patch),
                                   "--paths-output", str(paths), "--max-files", "1"], check=False)
        self.assertEqual(3, rejected.returncode)
        self.assertEqual("int add(int a, int b);\n", (self.repository / "calc.h").read_text())

    def test_patch_hunk_counts_are_normalized_from_literal_body(self):
        response = self.root / "malformed-count-response.md"
        response.write_text("""```diff
diff --git a/calc.c b/calc.c
--- a/calc.c
+++ b/calc.c
@@ -1,2 +1,2 @@
-int add(int a, int b) { return a + b; }
+int add(int a, int b) { return (a + b); }
```
""", encoding="utf-8")
        patch = self.root / "normalized-count.patch"
        paths = self.root / "normalized-count.paths"
        subprocess.run(["python3", str(ROOT / "tools/apply_worker_patch.py"),
                        "--repository", str(self.repository), "--response", str(response),
                        "--allowed-scope", "calc.c", "--patch-output", str(patch),
                        "--paths-output", str(paths), "--max-files", "1"], check=True)
        self.assertIn("@@ -1,1 +1,1 @@", patch.read_text())
        self.assertIn("return (a + b)", (self.repository / "calc.c").read_text())

    def test_architecture_normalization_emits_maps(self):
        output = self.root / "architecture"
        subprocess.run(["python3", str(ROOT / "tools/normalize_repository_architecture.py"),
                        "normalize", "--database", str(self.database), "--generation", "g",
                        "--output", str(output)], check=True)
        self.assertTrue((output / "responsibility-map.tsv").is_file())
        self.assertTrue((output / "findings.tsv").is_file())
        summary = (output / "summary.json").read_text()
        self.assertIn('"modules": 1', summary)

    def test_normative_projection_preserves_authority(self):
        output = self.root / "architecture"
        subprocess.run(["python3", str(ROOT / "tools/normalize_repository_architecture.py"),
                        "normalize", "--database", str(self.database), "--generation", "g",
                        "--output", str(output)], check=True)
        registry = self.root / "registry"
        registry.mkdir()
        (registry / "invariants.tsv").write_text(
            "invariant_id\tcategory\tauthority\tseverity\tstatement\tscope\tsource_requirement\tvalidation_kind\tvalidation_ref\taffected_nodes\n"
            "INV-add\tCONTRACT\tSPECIFICATION\tHIGH\tAddition remains public.\tcalc.c\tREQ-1\tCOMMAND\tcc -c calc.c\tn1\n",
            encoding="utf-8")
        (registry / "decisions.tsv").write_text(
            "decision_id\tstatus\tproducer_node\tproblem\tchosen_contract\taffected_interfaces\tsupersedes\tevidence\n"
            "DEC-add\tACCEPTED\tn1\taddition\tfunction\tadd\t-\tcalc.c\n", encoding="utf-8")
        (registry / "edges.tsv").write_text(
            "edge_id\tproducer_node\tconsumer_node\tcontract_artifact\tpublic_symbols\townership_model\trepresentation\tversioning_rule\tcompatibility_validation\tdecision_ids\tinvariant_ids\n"
            "EDGE-add\tn1\tn2\tcalc.h\tadd\tCALLEE\tC\tSTABLE\tcc -c calc.c\tDEC-add\tINV-add\n",
            encoding="utf-8")
        (registry / "node-bindings.tsv").write_text(
            "node_id\tinvariant_ids\tconsumes_decisions\tproduces_decisions\tedge_contracts\thealth_gates\n"
            "n1\tINV-add\t-\tDEC-add\tEDGE-add\t-\n", encoding="utf-8")
        projection = output / "normative-projection.tsv"
        subprocess.run(["python3", str(ROOT / "tools/project_normative_architecture.py"),
                        "--database", str(self.database), "--generation", "g",
                        "--architecture", str(registry), "--output", str(projection)], check=True)
        text = projection.read_text()
        self.assertIn("INVARIANT\tINV-add\tSPECIFICATION", text)
        self.assertIn("DECISION\tDEC-add\tNORMATIVE", text)
        self.assertIn("sym", text)

    def test_model_leaf_predictions_promotion_and_omissions(self):
        project = self.root / "project"
        logs = project / "logs"
        logs.mkdir(parents=True)
        header = ("recorded_at\tproject\tplan_node\ttask_id\trole\tmodel\tworker_route\t"
                  "complexity_score\tpredicted_actions\tpredicted_p95_tokens\tprocessed_tokens\t"
                  "usage_source\titems\tcommands\toutput_bytes\tmax_output_bytes\tsource_read_bytes\t"
                  "repeated_source_reads\tchanged_files\tduration_seconds\tclassification\tchanged_lines\t"
                  "planner_model\tplanner_effort\tleaf_type\n")
        rows = [
            "now\tp\tn1\tt1\tworker_luna\tgpt-5.6-luna\tLUNA\t4\t3\t100\t120\tactual\t3\t1\t4\t4\t4\t0\t1\t2\tsuccess\t1\tgpt-5.6-sol\thigh\tFOCUSED_BUG\n",
            "now\tp\tn2\tt2\tworker_luna\tgpt-5.6-luna\tLUNA\t5\t4\t200\t500\tactual\t4\t2\t8\t4\t8\t0\t1\t3\tsuccess\t1\tgpt-5.6-sol\thigh\tFOCUSED_BUG\n",
        ]
        (logs / "complexity-observations.tsv").write_text(header + "".join(rows), encoding="utf-8")
        (logs / "complexity-outcomes.tsv").write_text(
            "recorded_at\tproject\tplan_node\ttask_id\toutcome\troot_replans\tplanner_model\tplanner_effort\n"
            "now\tp\tn1\tt1\tACCEPTED\t0\tgpt-5.6-sol\thigh\n", encoding="utf-8")
        prediction = subprocess.run(
            ["python3", str(ROOT / "tools/context_closure_metrics.py"), "predictions",
             "--project", str(project)], check=True, text=True, stdout=subprocess.PIPE).stdout
        self.assertIn("gpt-5.6-luna\tFOCUSED_BUG\t2\t1", prediction)
        self.assertIn("\t500\t500\t", prediction)

        (logs / "context-closure-outcomes.tsv").write_text(
            "recorded_at\tproject\tplan_node\ttask_id\toutcome\tusage_report\tcommands\tclosure_paths\tused_paths\tunused_candidates\tmissing_candidates\tchanged_outside_closure\tclosure_status\n"
            "now\tp\tn1\tt1\tACCEPTED\tr\t1\t2\t2\t0\t0\t0\tREADY\n", encoding="utf-8")
        promotion = subprocess.run(
            ["python3", str(ROOT / "tools/context_closure_metrics.py"), "promotion",
             "--project", str(project), "--min-samples", "1", "--min-recall", "95",
             "--min-success", "80", "--max-false-block", "0"], check=True,
            text=True, stdout=subprocess.PIPE).stdout
        self.assertIn("status\tPROMOTABLE", promotion)

        (logs / "context-closure-usage-t1-x.tsv").write_text(
            "repository_path\tin_closure\trequirement\tread\tchanged\tadvisory_classification\n"
            "src/missing.c\tOUTSIDE_CLOSURE\t-\t1\t0\tMISSING_CANDIDATE\n", encoding="utf-8")
        omissions = subprocess.run(
            ["python3", str(ROOT / "tools/context_closure_metrics.py"), "omissions",
             "--project", str(project), "--minimum", "1"], check=True,
            text=True, stdout=subprocess.PIPE).stdout
        self.assertIn("src/missing.c\t1\tINDEX_OR_CLOSURE_REMEDIATION", omissions)

    def test_context_baseline_comparison_uses_verified_criteria(self):
        before = self.root / "before.tsv"
        after = self.root / "after.tsv"
        before.write_text("metric\tvalue\nprocessed_tokens\t1000\naccepted_outcomes\t1\ncheckpointed_outcomes\t1\n",
                          encoding="utf-8")
        after.write_text("metric\tvalue\nprocessed_tokens\t600\naccepted_outcomes\t2\ncheckpointed_outcomes\t1\n",
                         encoding="utf-8")
        compared = subprocess.run([str(ROOT / "bin/harness-compare-context-baselines"),
                                   str(before), str(after)], check=True, text=True,
                                  stdout=subprocess.PIPE).stdout
        self.assertIn("tokens_per_verified_criterion\t500\t200\t-300", compared)

    def test_recoll_candidates_use_project_overlay(self):
        fake = self.root / "recollq"
        fake.write_text(f"#!/bin/sh\nprintf '%s\\n' '{self.repository / 'calc.c'}'\n", encoding="utf-8")
        fake.chmod(0o755)
        overlay = self.root / "recoll.sqlite"
        report = self.root / "recoll.tsv"
        before = self.database.read_bytes()
        subprocess.run(["python3", str(ROOT / "tools/import_recoll_candidates.py"),
                        "--output-database", str(overlay), "--generation", "g",
                        "--repository", str(self.repository), "--recoll-bin", str(fake),
                        "--query", "addition", "--limit", "5", "--report", str(report)], check=True)
        self.assertEqual(before, self.database.read_bytes())
        connection = sqlite3.connect(overlay)
        self.assertEqual(1, connection.execute("SELECT count(*) FROM candidates").fetchone()[0])
        connection.close()
        self.assertIn("accepted\t1", report.read_text())


if __name__ == "__main__":
    unittest.main()
