#!/usr/bin/env python3

import subprocess
import sqlite3
import tempfile
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


class ContextRequestTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="context-request.")
        self.root = Path(self.temporary.name)
        self.repository = self.root / "repo"
        self.repository.mkdir()
        (self.repository / "calc.c").write_text(
            "typedef struct Number { int value; } Number;\n"
            "int add(Number n) { return n.value + 1; }\n"
            "int caller(void) { Number n = {1}; return add(n); }\n",
            encoding="utf-8",
        )
        (self.repository / "CMakeLists.txt").write_text(
            "add_library(calc calc.c)\n", encoding="utf-8")
        self.assignment = self.root / "assignment.md"
        self.assignment.write_text(
            "Task-ID: t1\nAllowed-Scope: calc.c\nContext-Paths: calc.c\n"
            "Required-Symbols: add\n", encoding="utf-8")
        self.closure = self.root / "closure.tsv"
        self.closure.write_text(
            "item_id\titem_kind\tsource_path\tstart_line\tend_line\tsymbol\tintroduced_by\trequired\tprovider\n"
            "one\tDEFINITION\tcalc.c\t2\t2\tadd\tseed\tREQUIRED\tscip\n",
            encoding="utf-8",
        )
        self.database = self.root / "architecture.sqlite"
        subprocess.run(["sqlite3", str(self.database)],
                       input=(ROOT / "formats/repository-index-schema.sql").read_bytes(), check=True)
        sql = """
        INSERT INTO index_generations VALUES('g','r','rev','c','i','sc','s','imp','bi','schema','READY','now');
        INSERT INTO build_configurations VALUES('c','g','compile_commands.json','c',NULL,NULL,'{}');
        INSERT INTO files VALUES(1,'g','calc.c','c',NULL,1,0);
        INSERT INTO source_regions VALUES(1,1,'definition','Number',1,0,1,49,NULL,'scip');
        INSERT INTO source_regions VALUES(2,1,'definition','add',2,0,2,44,NULL,'scip');
        INSERT INTO source_regions VALUES(3,1,'definition','caller',3,0,3,58,NULL,'scip');
        INSERT INTO symbols VALUES('type','g','Number','Struct','c','-','scip');
        INSERT INTO symbols VALUES('add','g','add','Function','c','-','scip');
        INSERT INTO symbols VALUES('caller','g','caller','Function','c','-','scip');
        INSERT INTO symbol_definitions VALUES('type',1,'definition','scip');
        INSERT INTO symbol_definitions VALUES('add',2,'definition','scip');
        INSERT INTO symbol_definitions VALUES('caller',3,'definition','scip');
        INSERT INTO type_edges VALUES('add','type','PARAMETER','scip');
        INSERT INTO call_edges VALUES('caller','add',3,'scip','AUTHORITATIVE');
        INSERT INTO mutation_edges VALUES('add','type','n.value',2,'joern','DERIVED');
        INSERT INTO build_targets VALUES('target','g','calc','STATIC_LIBRARY','CMakeLists.txt','cmake');
        INSERT INTO build_target_files VALUES('target',1,'c','COMPILE_SOURCE',NULL,'cmake');
        """
        subprocess.run(["sqlite3", str(self.database)], input=sql.encode(), check=True)

    def tearDown(self):
        self.temporary.cleanup()

    def resolve(self, kind: str, identifier: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run([
            "python3", str(ROOT / "tools/resolve_context_request.py"),
            "--assignment", str(self.assignment), "--closure", str(self.closure),
            "--database", str(self.database), "--repository", str(self.repository),
            "--request-kind", kind, "--identifier", identifier,
            "--output", str(self.root / "extension.md"), "--max-bytes", "4096",
        ], text=True, capture_output=True)

    def test_type_definition_is_limited_to_direct_type_neighbor(self):
        result = self.resolve("TYPE_DEFINITION", "Number")
        self.assertEqual(0, result.returncode, result.stderr + result.stdout)
        extension = (self.root / "extension.md").read_text(encoding="utf-8")
        self.assertIn("Authorization-Relation: required-or-direct-type", extension)
        self.assertIn("typedef struct Number", extension)
        self.assertIn("Evidence-SHA256:", extension)

    def test_direct_caller_contract_is_admitted(self):
        result = self.resolve("CALLER_CONTRACT", "add")
        self.assertEqual(0, result.returncode, result.stderr + result.stdout)
        self.assertIn("int caller(void)",
                      (self.root / "extension.md").read_text(encoding="utf-8"))

    def test_unrelated_symbol_is_rejected(self):
        result = self.resolve("TYPE_DEFINITION", "caller")
        self.assertNotEqual(0, result.returncode)
        self.assertIn("status=REJECTED", result.stdout)

    def test_build_owner_requires_declared_path(self):
        result = self.resolve("BUILD_OWNER", "calc.c")
        self.assertEqual(0, result.returncode, result.stderr + result.stdout)
        extension = (self.root / "extension.md").read_text(encoding="utf-8")
        self.assertIn("add_library(calc calc.c)", extension)

    def test_build_owner_accepts_declared_directory_boundary(self):
        (self.repository / "src").mkdir()
        (self.repository / "src" / "owned.c").write_text(
            "int owned(void) { return 1; }\n", encoding="utf-8")
        self.assignment.write_text(
            "Task-ID: t1\nAllowed-Scope: calc.c\nContext-Paths: calc.c\n"
            "Required-Symbols: add\nFocused-Validation: cmake -S src -B /tmp/build\n",
            encoding="utf-8")
        connection = sqlite3.connect(self.database)
        connection.execute("INSERT INTO files VALUES(2,'g','src/owned.c','c',NULL,1,0)")
        connection.execute(
            "INSERT INTO build_targets VALUES('owned-target','g','owned','STATIC_LIBRARY','CMakeLists.txt','cmake')")
        connection.execute(
            "INSERT INTO build_target_files VALUES('owned-target',2,'c','COMPILE_SOURCE',NULL,'cmake')")
        connection.commit()
        connection.close()

        result = self.resolve("BUILD_OWNER", "src")

        self.assertEqual(0, result.returncode, result.stderr + result.stdout)
        extension = (self.root / "extension.md").read_text(encoding="utf-8")
        self.assertIn("Authorization-Relation: build-owner-of-declared-path", extension)
        self.assertIn("add_library(calc calc.c)", extension)

    def test_failing_assertion_falls_back_inside_declared_directory(self):
        tests = self.repository / "tests"
        tests.mkdir()
        test_source = tests / "calc_test.c"
        test_source.write_text(
            "int IT_CALC_000(void) { return add((Number){1}) == 2; }\n",
            encoding="utf-8")
        self.assignment.write_text(
            "Task-ID: t1\nAllowed-Scope: calc.c\nContext-Paths: calc.c,tests\n"
            "Required-Symbols: add\n", encoding="utf-8")
        connection = sqlite3.connect(self.database)
        connection.execute("INSERT INTO files VALUES(2,'g','tests/calc_test.c','c',NULL,1,0)")
        connection.commit()
        connection.close()

        result = self.resolve("FAILING_ASSERTION", "IT_CALC_000")

        self.assertEqual(0, result.returncode, result.stderr + result.stdout)
        extension = (self.root / "extension.md").read_text(encoding="utf-8")
        self.assertIn("Authorization-Relation: exact-test-identifier-inside-assignment-boundary",
                      extension)
        self.assertIn("int IT_CALC_000", extension)
        self.assertIn("Provider: `declared-context-search`", extension)


if __name__ == "__main__":
    unittest.main()
