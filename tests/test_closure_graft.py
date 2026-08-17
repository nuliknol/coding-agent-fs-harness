#!/usr/bin/env python3

import csv
import subprocess
import tempfile
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


class ClosureGraftTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="closure-graft.")
        self.root = Path(self.temporary.name)
        self.assignment = self.root / "assignment.md"
        self.assignment.write_text(
            "Task-ID: t1\nSpecification-Obligations: REQ-1,REQ-2\n"
            "Affected-Invariants: INV-1\nEdge-Contracts: EDGE-1\n",
            encoding="utf-8",
        )
        self.children = self.root / "repair-children.tsv"
        fields = ("child_id", "parent_task", "sequence", "allowed_paths", "context_paths",
                  "required_symbols", "acceptance_evidence", "focused_validation", "source_cut",
                  "seam_kind", "estimated_source_bytes", "status")
        with self.children.open("w", encoding="utf-8", newline="") as stream:
            writer = csv.DictWriter(stream, fieldnames=fields, delimiter="\t", lineterminator="\n")
            writer.writeheader()
            writer.writerow(dict(zip(fields, (
                "CCR-a", "t1", "1", "a.c", "a.c", "a", "test-a", "test-a", "cut-a",
                "BUILD_TARGET", "100", "PROPOSED"))))
            writer.writerow(dict(zip(fields, (
                "CCR-b", "t1", "2", "b.c", "b.c", "b", "test-b", "test-b", "cut-b",
                "BUILD_TARGET", "100", "PROPOSED"))))

    def tearDown(self):
        self.temporary.cleanup()

    def compile(self) -> subprocess.CompletedProcess[str]:
        return subprocess.run([
            "python3", str(ROOT / "tools/compile_closure_graft.py"),
            "--assignment", str(self.assignment), "--repair-children", str(self.children),
            "--parent-criterion", "root.acceptance", "--output", str(self.root / "graft.tsv"),
            "--facets-output", str(self.root / "graft.tsv.facets.tsv"),
        ], text=True, capture_output=True)

    def test_graft_is_ordered_and_conserves_normative_facets(self):
        result = self.compile()
        self.assertEqual(0, result.returncode, result.stderr)
        with (self.root / "graft.tsv").open(encoding="utf-8", newline="") as stream:
            graft = list(csv.DictReader(stream, delimiter="\t"))
        self.assertEqual(["root.acceptance.CCR-a", "root.acceptance.CCR-b"],
                         [row["child_criterion"] for row in graft])
        with (self.root / "graft.tsv.facets.tsv").open(encoding="utf-8", newline="") as stream:
            facets = list(csv.DictReader(stream, delimiter="\t"))
        normative = {(row["facet_kind"], row["facet_id"]) for row in facets
                     if row["relation"] == "PRESERVES"}
        self.assertEqual({
            ("SPECIFICATION_OBLIGATION", "REQ-1"),
            ("SPECIFICATION_OBLIGATION", "REQ-2"),
            ("ARCHITECTURE_INVARIANT", "INV-1"),
            ("EDGE_CONTRACT", "EDGE-1"),
        }, normative)
        seams = [row["facet_id"] for row in facets if row["relation"] == "IMPLEMENTS"]
        self.assertEqual(["CCR-a", "CCR-b"], seams)

    def test_single_child_is_not_a_semantic_decomposition(self):
        lines = self.children.read_text(encoding="utf-8").splitlines()
        self.children.write_text("\n".join(lines[:2]) + "\n", encoding="utf-8")
        result = self.compile()
        self.assertNotEqual(0, result.returncode)
        self.assertIn("at least two", result.stderr)


if __name__ == "__main__":
    unittest.main()
