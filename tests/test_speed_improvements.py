#!/usr/bin/env python3

import csv
import re
import sqlite3
import subprocess
import tempfile
import unittest
from pathlib import Path

from tools.apply_worker_patch import validate_mutation_regions


ROOT = Path(__file__).resolve().parents[1]


class SpeedImprovementTests(unittest.TestCase):
    def test_deterministic_continuation_has_one_canonical_target(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            assignment = root / "assignment.md"
            assignment.write_text(
                "# Harness Continuation Context\n\nTask-ID: old\nTask-Root: root\n"
                "Target-Criterion: old.target\nManager-Remediation: 1\n"
                "Blocker-Class: LOCAL_CODE_PREREQUISITE\n"
                "Goal-ID: old-goal\nAllowed-Scope: src/old.c\n\n## Objective\nKeep me.\n",
                encoding="utf-8")
            children = root / "children.tsv"
            children.write_text(
                "child_id\tparent_task\tsequence\tallowed_paths\tcontext_paths\t"
                "required_symbols\tacceptance_evidence\tfocused_validation\n"
                "cut-1\told\t1\tsrc/new.c\tsrc/new.c\tnew_symbol\tpasses\ttrue\n",
                encoding="utf-8")
            output = root / "continuation.md"
            subprocess.run([
                "python3", str(ROOT / "tools/compile_deterministic_continuation.py"),
                "--assignment", str(assignment), "--repair-children", str(children),
                "--output", str(output), "--task-id", "root-revision-01",
                "--task-root", "root", "--target-criterion", "root.acceptance.01",
                "--supersedes", "old", "--manager-remediation", "--closure-cut"],
                check=True, capture_output=True, text=True)
            rendered = output.read_text(encoding="utf-8")
            self.assertEqual(rendered.count("Task-ID: "), 1)
            self.assertEqual(rendered.count("Task-Root: "), 1)
            self.assertEqual(rendered.count("Target-Criterion: "), 1)
            self.assertIn("Target-Criterion: root.acceptance.01", rendered)
            self.assertIn("Context-Closure-Cut: cut-1", rendered)
            self.assertIn("## Objective\nKeep me.", rendered)
            self.assertIn("## Acceptance criteria\n\npasses", rendered)
            self.assertIn("## Validation commands\n\ntrue", rendered)

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
            events.write_text(
                "2026-08-18T00:00:00Z\tWORKER_INVOCATION_STARTED task=a session=s1 attempt=1\n"
                "2026-08-18T00:01:00Z\tWORKER_INVOCATION_FINISHED task=a session=s1 attempt=1\n"
                "2026-08-18T00:02:00Z\tWORKER_INVOCATION_STARTED task=b session=legacy attempt=1\n",
                encoding="utf-8")
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
            self.assertEqual(metrics["worker_occupied_seconds"], "60")
            self.assertEqual(metrics["worker_unclosed_intervals"], "1")
            self.assertEqual(metrics["worker_slot_utilization_percent"], "12.50")

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

    def test_validation_command_build_broker_resolves_registered_source(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            database = root / "architecture.sqlite"
            connection = sqlite3.connect(database)
            connection.executescript("""
                CREATE TABLE files(file_id INTEGER, repository_path TEXT);
                CREATE TABLE build_targets(target_id TEXT, name TEXT, target_kind TEXT,
                                           definition_path TEXT);
                CREATE TABLE build_target_files(target_id TEXT, file_id INTEGER, role TEXT,
                                                object_path TEXT);
                CREATE TABLE tests(name TEXT, build_target TEXT, selector TEXT, file_id INTEGER);
                INSERT INTO files VALUES(1,'tests/render_compile/render_compile_tests.hip');
                INSERT INTO build_targets VALUES('t1','dpvis_render_compile_tests','EXECUTABLE',
                                                 'tests/render_compile/CMakeLists.txt');
                INSERT INTO build_target_files VALUES('t1',1,'COMPILE_SOURCE','test.o');
                INSERT INTO tests VALUES('IT-RCP-000','dpvis_render_compile_tests',
                                         '^IT-RCP-000$',1);
            """)
            connection.commit()
            connection.close()
            pointer = root / "pointer.env"
            pointer.write_text(f"status=READY\ngeneration_dir={root}\n", encoding="utf-8")
            command = ("cmake --build /tmp/build --target dpvis_render_compile_tests && "
                       "ctest --test-dir /tmp/build -R '^IT-RCP-000$'")
            output = subprocess.check_output([
                "python3", str(ROOT / "tools/query_build_broker.py"),
                "--pointer", str(pointer), "--query", "VALIDATION_COMMAND",
                "--value", command], text=True)
            self.assertIn("BUILD_TARGET_SOURCE\tdpvis_render_compile_tests\t"
                          "dpvis_render_compile_tests\t"
                          "tests/render_compile/render_compile_tests.hip", output)
            self.assertIn("TEST_SELECTOR\t^IT-RCP-000$\t"
                          "dpvis_render_compile_tests\t"
                          "tests/render_compile/render_compile_tests.hip", output)

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

    def test_partial_symbol_capabilities_fall_back_to_allowed_scope(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            database = root / "architecture.sqlite"
            connection = sqlite3.connect(database)
            connection.executescript("""
                CREATE TABLE symbols(symbol_id TEXT, display_name TEXT, symbol_kind TEXT);
                CREATE TABLE symbol_definitions(symbol_id TEXT, region_id INTEGER);
                CREATE TABLE source_regions(region_id INTEGER, file_id INTEGER, start_line INTEGER, end_line INTEGER);
                CREATE TABLE files(file_id INTEGER, repository_path TEXT);
                INSERT INTO symbols VALUES('s','resolved_target','function');
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
                "n1\tsrc/a.c\tresolved_target,unindexed_target\tLOCAL_IMPLEMENTATION\tLUNA\n",
                encoding="utf-8")
            output = root / "out.tsv"
            result = subprocess.run([
                "python3", str(ROOT / "tools/compile_mutation_capabilities.py"),
                "--plan", str(plan), "--pointer", str(pointer), "--output", str(output)],
                text=True, capture_output=True)
            self.assertEqual(result.returncode, 0)
            with output.open(encoding="utf-8", newline="") as stream:
                self.assertEqual(list(csv.DictReader(stream, delimiter="\t")), [])

    def test_mutation_capability_relocates_live_braced_definition(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            repository = root / "repo"
            (repository / "src").mkdir(parents=True)
            (repository / "src" / "a.c").write_text(
                "/* checkpointed prefix */\n" * 10 +
                "int target(int value)\n{\n"
                "    value += 1;\n"
                "    return value;\n}\n",
                encoding="utf-8",
            )
            database = root / "architecture.sqlite"
            connection = sqlite3.connect(database)
            connection.executescript("""
                CREATE TABLE symbols(symbol_id TEXT, display_name TEXT, symbol_kind TEXT);
                CREATE TABLE symbol_definitions(symbol_id TEXT, region_id INTEGER);
                CREATE TABLE source_regions(region_id INTEGER, file_id INTEGER, start_line INTEGER, end_line INTEGER);
                CREATE TABLE files(file_id INTEGER, repository_path TEXT);
                INSERT INTO symbols VALUES('s','target','function');
                INSERT INTO files VALUES(1,'src/a.c');
                INSERT INTO source_regions VALUES(1,1,1,5);
                INSERT INTO symbol_definitions VALUES('s',1);
            """)
            connection.commit()
            connection.close()
            pointer = root / "pointer.env"
            pointer.write_text(f"status=READY\ngeneration_dir={root}\n", encoding="utf-8")
            plan = root / "plan.tsv"
            plan.write_text(
                "node_id\tallowed_paths\trequired_symbols\tleaf_type\tworker_route\n"
                "n1\tsrc/a.c\ttarget\tLOCAL_IMPLEMENTATION\tLUNA\n", encoding="utf-8")
            output = root / "out.tsv"

            result = subprocess.run([
                "python3", str(ROOT / "tools/compile_mutation_capabilities.py"),
                "--plan", str(plan), "--pointer", str(pointer),
                "--repository", str(repository), "--output", str(output)],
                text=True, capture_output=True)

            self.assertEqual(0, result.returncode, result.stderr)
            with output.open(encoding="utf-8", newline="") as stream:
                rows = list(csv.DictReader(stream, delimiter="\t"))
            self.assertEqual("11", rows[0]["start_line"])
            self.assertEqual("15", rows[0]["end_line"])
            self.assertEqual("INDEXED_LIVE_RELOCATED", rows[0]["authority"])

    def test_assignment_capability_and_mutation_region_resolution(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            repository = root / "repo"
            (repository / "src").mkdir(parents=True)
            (repository / "src" / "a.c").write_text(
                "int first(void) { return 1; }\n\n"
                "int provider(void) { return first(); }\n",
                encoding="utf-8")
            database = root / "architecture.sqlite"
            connection = sqlite3.connect(database)
            connection.executescript("""
                CREATE TABLE symbols(symbol_id TEXT, display_name TEXT, symbol_kind TEXT);
                CREATE TABLE symbol_definitions(symbol_id TEXT, region_id INTEGER);
                CREATE TABLE source_regions(region_id INTEGER, file_id INTEGER, start_line INTEGER, end_line INTEGER);
                CREATE TABLE files(file_id INTEGER, repository_path TEXT);
                INSERT INTO symbols VALUES('first','first','function');
                INSERT INTO symbols VALUES('provider','provider','function');
                INSERT INTO files VALUES(1,'src/a.c');
                INSERT INTO source_regions VALUES(1,1,1,1);
                INSERT INTO source_regions VALUES(2,1,3,3);
                INSERT INTO symbol_definitions VALUES('first',1);
                INSERT INTO symbol_definitions VALUES('provider',2);
            """)
            connection.commit()
            connection.close()
            pointer = root / "pointer.env"
            pointer.write_text(f"status=READY\ngeneration_dir={root}\n", encoding="utf-8")
            assignment = root / "assignment.md"
            assignment.write_text(
                "Allowed-Scope: src/a.c\nRequired-Symbols: first,provider\n"
                "Leaf-Type: FOCUSED_BUG\nWorker-Route: LUNA\n",
                encoding="utf-8")
            output = root / "out.tsv"
            result = subprocess.run([
                "python3", str(ROOT / "tools/compile_mutation_capabilities.py"),
                "--assignment", str(assignment), "--node-id", "n1",
                "--pointer", str(pointer), "--repository", str(repository),
                "--output", str(output), "--require-complete-source"],
                text=True, capture_output=True)
            self.assertEqual(0, result.returncode, result.stderr)
            with output.open(encoding="utf-8", newline="") as stream:
                self.assertEqual({"first", "provider"},
                                 {row["symbol"] for row in csv.DictReader(stream, delimiter="\t")})
            resolved = subprocess.check_output([
                "python3", str(ROOT / "tools/resolve_mutation_region.py"),
                "--pointer", str(pointer), "--repository", str(repository),
                "--identifier", "src/a.c:3"], text=True).strip()
            self.assertEqual("src/a.c\tprovider", resolved)

    def test_file_local_overlay_symbol_compiles_exact_mutation_region(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            repository = root / "repo"
            (repository / "src").mkdir(parents=True)
            (repository / "src" / "a.c").write_text(
                "int provider(void)\n{\n"
                "    int checkpoint_digest = 1;\n"
                "    return checkpoint_digest;\n"
                "}\n",
                encoding="utf-8")
            database = root / "architecture.sqlite"
            connection = sqlite3.connect(database)
            connection.executescript("""
                CREATE TABLE symbols(symbol_id TEXT, display_name TEXT, symbol_kind TEXT);
                CREATE TABLE symbol_definitions(symbol_id TEXT, region_id INTEGER);
                CREATE TABLE source_regions(region_id INTEGER, file_id INTEGER, start_line INTEGER, end_line INTEGER);
                CREATE TABLE files(file_id INTEGER, repository_path TEXT);
                INSERT INTO symbols VALUES('provider','provider','function');
                INSERT INTO files VALUES(1,'src/a.c');
                INSERT INTO source_regions VALUES(1,1,1,5);
                INSERT INTO symbol_definitions VALUES('provider',1);
            """)
            connection.commit()
            connection.close()
            pointer = root / "pointer.env"
            pointer.write_text(f"status=READY\ngeneration_dir={root}\n", encoding="utf-8")
            assignment = root / "assignment.md"
            assignment.write_text(
                "Allowed-Scope: src/a.c\nRequired-Symbols: checkpoint_digest\n"
                "Leaf-Type: LOCAL_IMPLEMENTATION\nWorker-Route: LUNA\n",
                encoding="utf-8")
            output = root / "out.tsv"
            result = subprocess.run([
                "python3", str(ROOT / "tools/compile_mutation_capabilities.py"),
                "--assignment", str(assignment), "--node-id", "n1",
                "--pointer", str(pointer), "--repository", str(repository),
                "--output", str(output), "--require-complete-source"],
                text=True, capture_output=True)
            self.assertEqual(0, result.returncode, result.stderr)
            with output.open(encoding="utf-8", newline="") as stream:
                rows = list(csv.DictReader(stream, delimiter="\t"))
            self.assertEqual(1, len(rows))
            self.assertEqual("checkpoint_digest", rows[0]["symbol"])
            self.assertEqual("2", rows[0]["start_line"])
            self.assertEqual("5", rows[0]["end_line"])
            self.assertEqual("LEXICAL_LOCAL_ALLOWED_FILE", rows[0]["authority"])

    def test_unresolved_symbol_cannot_use_local_capability_fallback(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            repository = root / "repo"
            (repository / "src").mkdir(parents=True)
            (repository / "src" / "a.c").write_text(
                "int provider(void) { return 1; }\n", encoding="utf-8")
            database = root / "architecture.sqlite"
            connection = sqlite3.connect(database)
            connection.executescript("""
                CREATE TABLE symbols(symbol_id TEXT, display_name TEXT, symbol_kind TEXT);
                CREATE TABLE symbol_definitions(symbol_id TEXT, region_id INTEGER);
                CREATE TABLE source_regions(region_id INTEGER, file_id INTEGER, start_line INTEGER, end_line INTEGER);
                CREATE TABLE files(file_id INTEGER, repository_path TEXT);
            """)
            connection.commit()
            connection.close()
            pointer = root / "pointer.env"
            pointer.write_text(f"status=READY\ngeneration_dir={root}\n", encoding="utf-8")
            assignment = root / "assignment.md"
            assignment.write_text(
                "Allowed-Scope: src/a.c\nRequired-Symbols: invented_symbol\n"
                "Leaf-Type: LOCAL_IMPLEMENTATION\nWorker-Route: LUNA\n",
                encoding="utf-8")
            result = subprocess.run([
                "python3", str(ROOT / "tools/compile_mutation_capabilities.py"),
                "--assignment", str(assignment), "--node-id", "n1",
                "--pointer", str(pointer), "--repository", str(repository),
                "--output", str(root / "out.tsv"), "--require-complete-source"],
                text=True, capture_output=True)
            self.assertEqual(3, result.returncode)
            self.assertIn("Required-Symbols are absent from the repository index", result.stderr)

    def test_validation_build_rewrite_covers_direct_execution(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            private = root / "private"
            logical = root / "shared-build"
            command = (f"cmake -S dplm -B {logical} && "
                       f"cmake --build {logical} --target smoke && "
                       f"{logical}/smoke && ctest --test-dir {logical} -R smoke")
            output = subprocess.check_output([
                "python3", str(ROOT / "tools/rewrite_validation_build_paths.py"),
                "--command", command, "--cwd", str(root),
                "--private-root", str(private)], text=True).strip()
            self.assertNotIn(str(logical), output)
            rewritten_paths = re.findall(re.escape(str(private)) + r"/[0-9a-f]{64}", output)
            self.assertEqual(len(rewritten_paths), 4)
            self.assertEqual(len(set(rewritten_paths)), 1)


if __name__ == "__main__":
    unittest.main()
