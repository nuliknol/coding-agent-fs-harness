#!/usr/bin/env python3

import csv
import os
from pathlib import Path
import sqlite3
import subprocess
import tempfile
import unittest
from types import SimpleNamespace


ROOT = Path(__file__).resolve().parents[1]
import sys
sys.path.insert(0, str(ROOT / "tools"))
from context_closure import build_closure


class ContextClosureToolsTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="context-closure-tools.")
        self.root = Path(self.temporary.name)
        self.repository = self.root / "repo"
        self.repository.mkdir()
        subprocess.run(["git", "init", "-q", str(self.repository)], check=True)
        (self.repository / "calc.c").write_text("int add(int a, int b) { return a + b; }\n", encoding="utf-8")
        (self.repository / "calc.h").write_text("int add(int a, int b);\n", encoding="utf-8")
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

    def closure(self, extra: str = "", omissions: Path | None = None) -> tuple[str, Path]:
        assignment = self.root / "assignment.md"
        assignment.write_text(
            "Task-ID: t1\nPlan-Node: n1\nWorker-Route: LUNA\nAllowed-Scope: calc.c\n"
            "Context-Paths: calc.c\nRequired-Symbols: add\n" + extra, encoding="utf-8")
        output = self.root / ("closure-" + str(len(list(self.root.glob("closure-*")))))
        arguments = SimpleNamespace(
            assignment=str(assignment), database=str(self.database), repository=str(self.repository),
            generation="g", output=str(output), max_bytes=32768, max_symbols=32, max_modules=4,
            max_ownership_boundaries=2, max_direct_relationships=8, max_tests=4,
            max_build_targets=4, max_tokens=10000, obligations_file=None, relations_file=None,
            invariants_file=None, decisions_file=None, edges_file=None, health_gates_file=None,
            node_bindings_file=None, omissions_file=str(omissions) if omissions else None)
        return build_closure(arguments), output

    def test_conflicting_configuration_fails_closed(self):
        connection = sqlite3.connect(self.database)
        connection.execute("INSERT INTO build_configurations VALUES('other','g','other.json','other',NULL,NULL,'{}')")
        connection.commit()
        connection.close()
        status, output = self.closure()
        self.assertEqual("INCOMPLETE", status)
        self.assertIn("multiple indexed configurations", (output / "unresolved.tsv").read_text())

    def test_requested_flow_without_joern_fails_closed(self):
        status, output = self.closure("Required-Dependency-Classes: D,F\n")
        self.assertEqual("INCOMPLETE", status)
        self.assertIn("Joern flow evidence was requested", (output / "unresolved.tsv").read_text())

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
