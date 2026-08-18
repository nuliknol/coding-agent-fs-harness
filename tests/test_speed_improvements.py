#!/usr/bin/env python3

import csv
import sqlite3
import subprocess
import tempfile
import unittest
from pathlib import Path

from tools.apply_worker_patch import validate_mutation_regions


ROOT = Path(__file__).resolve().parents[1]


class SpeedImprovementTests(unittest.TestCase):
    def test_parallelism_and_conflict_reduced_width(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            plan = root / "plan.tsv"
            plan.write_text(
                "node_id\tparent_id\tdepends_on\tdeliverable\tacceptance_evidence\t"
                "focused_validation\tallowed_paths\trequired_symbols\tleaf_type\t"
                "complexity_class\tworker_route\n"
                "a\t-\t-\ta\ta\ttrue\tsrc/a.c\ta\tLOCAL_IMPLEMENTATION\tLOW\tLUNA\n"
                "b\t-\t-\tb\tb\ttrue\tsrc/b.c\tb\tLOCAL_IMPLEMENTATION\tLOW\tLUNA\n"
                "c\t-\ta\tc\tc\ttrue\tsrc/c.c\tc\tLOCAL_IMPLEMENTATION\tLOW\tLUNA\n"
                "d\t-\tb\td\td\ttrue\tsrc/d.c\td\tLOCAL_IMPLEMENTATION\tLOW\tLUNA\n",
                encoding="utf-8")
            state = root / "state.tsv"
            state.write_text("# item_id\tstatus\ttask_root\tupdated_at\n" +
                             "".join(f"{node}\tPENDING\t-\tnow\n" for node in "abcd"),
                             encoding="utf-8")
            conflicts = root / "conflicts.tsv"
            conflicts.write_text("left_node\tright_node\treasons\na\tb\tarchitecture:test\n",
                                 encoding="utf-8")
            events = root / "events.log"
            events.write_text("", encoding="utf-8")
            output = subprocess.check_output([
                "python3", str(ROOT / "tools/analyze_decomposition_parallelism.py"),
                "--plan", str(plan), "--state", str(state), "--events", str(events),
                "--capacity", "4", "--conflicts", str(conflicts)], text=True)
            metrics = dict(line.split("=", 1) for line in output.splitlines())
            self.assertEqual(metrics["critical_path_length"], "2")
            self.assertEqual(metrics["maximum_dag_width"], "2")
            self.assertEqual(metrics["dependency_ready_width"], "2")
            self.assertEqual(metrics["safe_ready_width"], "1")
            self.assertEqual(metrics["conflict_reduced_max_width"], "2")

    def test_disjoint_indexed_regions_remove_same_file_conflict(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            plan = root / "plan.tsv"
            plan.write_text(
                "node_id\tallowed_paths\trequired_symbols\n"
                "left\tsrc/shared.c\tleft_symbol\nright\tsrc/shared.c\tright_symbol\n",
                encoding="utf-8")
            capabilities = root / "capabilities.tsv"
            capabilities.write_text(
                "node_id\trepository_path\tsymbol\tstart_line\tend_line\tsymbol_kind\tauthority\n"
                "left\tsrc/shared.c\tleft_symbol\t1\t10\tfunction\tINDEXED\n"
                "right\tsrc/shared.c\tright_symbol\t20\t30\tfunction\tINDEXED\n",
                encoding="utf-8")
            output = root / "conflicts.tsv"
            subprocess.run(["python3", str(ROOT / "tools/compile_plan_conflicts.py"),
                            "--plan", str(plan), "--capabilities", str(capabilities),
                            "--output", str(output)], check=True)
            with output.open(encoding="utf-8", newline="") as stream:
                self.assertEqual(list(csv.DictReader(stream, delimiter="\t")), [])

    def test_patch_region_rejects_outside_change(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            capabilities = Path(directory) / "capabilities.tsv"
            capabilities.write_text(
                "node_id\trepository_path\tsymbol\tstart_line\tend_line\tsymbol_kind\tauthority\n"
                "n1\tsrc/a.c\ttarget\t10\t20\tfunction\tINDEXED\n", encoding="utf-8")
            valid = "diff --git a/src/a.c b/src/a.c\n--- a/src/a.c\n+++ b/src/a.c\n@@ -12,1 +12,1 @@\n-old\n+new\n"
            validate_mutation_regions(valid, capabilities, "n1")
            invalid = valid.replace("-12,1 +12,1", "-30,1 +30,1")
            with self.assertRaisesRegex(ValueError, "outside indexed Mutation-Regions"):
                validate_mutation_regions(invalid, capabilities, "n1")

    def test_exact_luna_file_requirement_from_index(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            database = root / "architecture.sqlite"
            connection = sqlite3.connect(database)
            connection.executescript("""
                CREATE TABLE symbols(symbol_id TEXT, display_name TEXT, symbol_kind TEXT);
                CREATE TABLE symbol_definitions(symbol_id TEXT, region_id INTEGER);
                CREATE TABLE source_regions(region_id INTEGER, file_id INTEGER, start_line INTEGER, end_line INTEGER);
                CREATE TABLE files(file_id INTEGER, repository_path TEXT);
                INSERT INTO symbols VALUES('s','target','function');
                INSERT INTO files VALUES(1,'src/a.c');
                INSERT INTO source_regions VALUES(1,1,4,8);
                INSERT INTO symbol_definitions VALUES('s',1);
            """)
            connection.commit()
            connection.close()
            pointer = root / "pointer.env"
            pointer.write_text(f"status=READY\ngeneration_dir={root}\n", encoding="utf-8")
            plan = root / "plan.tsv"
            plan.write_text(
                "node_id\tallowed_paths\trequired_symbols\tleaf_type\tworker_route\n"
                "n1\tsrc\ttarget\tLOCAL_IMPLEMENTATION\tLUNA\n", encoding="utf-8")
            result = subprocess.run([
                "python3", str(ROOT / "tools/compile_mutation_capabilities.py"),
                "--plan", str(plan), "--pointer", str(pointer), "--output", str(root / "out.tsv"),
                "--require-exact-luna"], text=True, capture_output=True)
            self.assertEqual(result.returncode, 3)
            self.assertIn("replace broad allowed_paths src with exact source files", result.stderr)


if __name__ == "__main__":
    unittest.main()
