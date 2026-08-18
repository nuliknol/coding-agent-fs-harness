#!/usr/bin/env python3

import csv
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from architecture.benchmarks import benchmark_maps
from architecture.inference import infer_findings
from architecture.providers import BashProvider, PythonProvider
from architecture.scorecard import from_maps, write_scorecard
from architecture.reporting import write_snapshot


class ArchitectureToolsTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="architecture-tools.")
        self.root = Path(self.temporary.name)
        self.repository = self.root / "repo"
        (self.repository / "lib").mkdir(parents=True)
        (self.repository / "bin").mkdir()
        (self.repository / "tests").mkdir()
        (self.repository / "py").mkdir()
        (self.repository / "lib/state.sh").write_text("""#!/usr/bin/env bash
state_read() { printf '%s\\n' "$HARNESS_STATE"; }
state_write() { printf 'status=ready\\n' > "$PROJECT_DIR/control/state.env"; }
""", encoding="utf-8")
        (self.repository / "lib/other.sh").write_text("""#!/usr/bin/env bash
other_action() { state_read; }
""", encoding="utf-8")
        (self.repository / "bin/run").write_text("""#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/state.sh"
usage() { :; }
state_read
""", encoding="utf-8")
        (self.repository / "tests/test-run.sh").write_text("""#!/usr/bin/env bash
usage() { :; }
""", encoding="utf-8")
        (self.repository / "py/base.py").write_text("def public_api():\n    return 1\n", encoding="utf-8")
        (self.repository / "py/use.py").write_text("from py.base import public_api\n", encoding="utf-8")
        subprocess.run(["git", "-C", str(self.repository), "init", "-q"], check=True)
        subprocess.run(["git", "-C", str(self.repository), "add", "."], check=True)
        subprocess.run(["git", "-C", str(self.repository), "-c", "user.name=test", "-c",
                        "user.email=test@example.invalid", "commit", "-qm", "seed"], check=True)

    def tearDown(self):
        self.temporary.cleanup()

    def snapshot(self):
        snapshot = BashProvider(self.repository, "g").collect()
        snapshot.merge(PythonProvider(self.repository, "g").collect())
        infer_findings(snapshot, high_fanout=20)
        return snapshot

    def test_bash_and_python_providers_emit_semantic_edges(self):
        snapshot = self.snapshot()
        kinds = {module.kind for module in snapshot.modules}
        self.assertIn("SHELL_LIBRARY", kinds)
        self.assertIn("SHELL_COMMAND", kinds)
        self.assertIn("PYTHON_MODULE", kinds)
        self.assertIn("SOURCES", {edge.kind for edge in snapshot.dependencies})
        self.assertIn("IMPORTS", {edge.kind for edge in snapshot.dependencies})
        self.assertIn("CONFIGURATION", {state.state_kind for state in snapshot.state_accesses})
        self.assertIn("PROJECT_ARTIFACT", {state.state_kind for state in snapshot.state_accesses})
        ambiguous = {finding.subject for finding in snapshot.findings
                     if finding.kind == "AMBIGUOUS_CONCEPT_OWNER"}
        self.assertNotIn("shell-function:usage", ambiguous)

    def test_maps_scorecard_benchmarks_and_directional_comparison(self):
        maps = self.root / "maps"
        write_snapshot(maps, self.snapshot())
        ownership_header = (maps / "ownership-map.tsv").read_text().splitlines()[0]
        concept_header = (maps / "concept-owner-map.tsv").read_text().splitlines()[0]
        self.assertNotEqual(ownership_header, concept_header)
        queries = self.root / "queries.tsv"
        queries.write_text("benchmark_id\tquery\texpected_paths\nb1\tstate_read\tlib/state.sh\n", encoding="utf-8")
        benchmarks = self.root / "benchmarks.tsv"
        benchmark_maps(maps, self.repository, queries, benchmarks)
        with benchmarks.open(encoding="utf-8", newline="") as stream:
            rows = list(csv.DictReader(stream, delimiter="\t"))
        self.assertEqual("1", rows[0]["relevant_returned"])
        metrics, findings = from_maps(maps, "g", benchmarks)
        self.assertEqual(2, metrics["schema_version"])
        self.assertTrue(str(metrics["benchmark_set_sha256"]).startswith("sha256:"))
        scorecard = self.root / "scorecard.tsv"
        proposal = self.root / "proposal.md"
        write_scorecard(scorecard, proposal, metrics, findings)
        self.assertEqual("metric\tvalue\tdirection\tregression_threshold",
                         scorecard.read_text().splitlines()[0])
        result = subprocess.run(
            ["python3", str(ROOT / "tools/compare_architecture_scorecards.py"),
             str(scorecard), str(scorecard)], text=True, stdout=subprocess.PIPE, check=True)
        self.assertIn("comparison_status\tPASS", result.stdout)

        regressed = self.root / "regressed.tsv"
        rows = list(csv.DictReader(scorecard.read_text(encoding="utf-8").splitlines(), delimiter="\t"))
        for row in rows:
            if row["metric"] == "cycles":
                row["value"] = str(int(row["value"]) + 1)
        with regressed.open("w", encoding="utf-8", newline="") as stream:
            writer = csv.DictWriter(stream, fieldnames=list(rows[0]), delimiter="\t", lineterminator="\n")
            writer.writeheader()
            writer.writerows(rows)
        result = subprocess.run(
            ["python3", str(ROOT / "tools/compare_architecture_scorecards.py"),
             str(scorecard), str(regressed)], text=True, stdout=subprocess.PIPE)
        self.assertEqual(4, result.returncode)
        self.assertIn("comparison_status\tREGRESSION", result.stdout)

        mismatched = self.root / "mismatched.tsv"
        for row in rows:
            if row["metric"] == "benchmark_set_sha256":
                row["value"] = "sha256:" + "0" * 64
        with mismatched.open("w", encoding="utf-8", newline="") as stream:
            writer = csv.DictWriter(stream, fieldnames=list(rows[0]), delimiter="\t", lineterminator="\n")
            writer.writeheader()
            writer.writerows(rows)
        result = subprocess.run(
            ["python3", str(ROOT / "tools/compare_architecture_scorecards.py"),
             str(scorecard), str(mismatched)], text=True, stdout=subprocess.PIPE)
        self.assertEqual(3, result.returncode)
        self.assertIn("comparison_status\tINCOMPARABLE", result.stdout)

    def test_source_only_cli_is_reproducible(self):
        first = self.root / "first"
        second = self.root / "second"
        for output in (first, second):
            subprocess.run(["python3", str(ROOT / "tools/source_architecture.py"),
                            "--repository", str(self.repository), "--output", str(output)], check=True)
        self.assertEqual((first / "manifest.json").read_text(), (second / "manifest.json").read_text())
        self.assertEqual((first / "dependency-map.tsv").read_text(),
                         (second / "dependency-map.tsv").read_text())


if __name__ == "__main__":
    unittest.main()
