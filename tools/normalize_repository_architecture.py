#!/usr/bin/env python3

"""Derive reproducible architecture maps, findings, benchmarks, and scorecards."""

import argparse
import csv
import hashlib
import json
from pathlib import Path
import sqlite3


def stable_id(*parts: str) -> str:
    return hashlib.sha256("\0".join(parts).encode()).hexdigest()


def rows(connection: sqlite3.Connection, query: str, parameters=()) -> list[sqlite3.Row]:
    return connection.execute(query, parameters).fetchall()


def write_tsv(path: Path, columns: tuple[str, ...], records: list[tuple]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream, delimiter="\t", lineterminator="\n")
        writer.writerow(columns)
        writer.writerows(records)


def strongly_connected(graph: dict[str, set[str]]) -> list[list[str]]:
    index = 0
    stack: list[str] = []
    indexes: dict[str, int] = {}
    low: dict[str, int] = {}
    on_stack: set[str] = set()
    components: list[list[str]] = []

    def visit(node: str) -> None:
        nonlocal index
        indexes[node] = low[node] = index
        index += 1
        stack.append(node)
        on_stack.add(node)
        for target in sorted(graph.get(node, set())):
            if target not in indexes:
                visit(target)
                low[node] = min(low[node], low[target])
            elif target in on_stack:
                low[node] = min(low[node], indexes[target])
        if low[node] == indexes[node]:
            component: list[str] = []
            while stack:
                member = stack.pop()
                on_stack.remove(member)
                component.append(member)
                if member == node:
                    break
            if len(component) > 1:
                components.append(sorted(component))

    for node in sorted(graph):
        if node not in indexes:
            visit(node)
    return components


def infer(args: argparse.Namespace) -> None:
    output = Path(args.output)
    output.mkdir(parents=True, exist_ok=True)
    connection = sqlite3.connect(args.database)
    connection.row_factory = sqlite3.Row
    generation = args.generation
    try:
        connection.execute("BEGIN IMMEDIATE")
        connection.execute("DELETE FROM architecture_findings WHERE generation_id=?", (generation,))
        connection.execute("DELETE FROM module_edges WHERE source_module_id IN (SELECT module_id FROM modules WHERE generation_id=? AND authority='DERIVED')", (generation,))
        connection.execute("DELETE FROM modules WHERE generation_id=? AND authority='DERIVED'", (generation,))
        connection.execute("DELETE FROM concept_owners WHERE authority='DERIVED' AND provider='architecture-normalizer'")

        file_modules: dict[int, set[str]] = {}
        responsibility: list[tuple] = []
        target_rows = rows(connection, """
            SELECT bt.target_id,bt.name,bt.target_kind,bt.definition_path,btf.file_id,f.repository_path
            FROM build_targets bt JOIN build_target_files btf USING(target_id)
            JOIN files f USING(file_id) WHERE bt.generation_id=? ORDER BY bt.name,f.repository_path""", (generation,))
        for row in target_rows:
            module_id = "build:" + row["target_id"]
            connection.execute(
                "INSERT OR IGNORE INTO modules VALUES(?,?,?,?,?,'architecture-normalizer','DERIVED')",
                (module_id, generation, row["name"], row["target_kind"] or "BUILD_TARGET",
                 row["definition_path"] or Path(row["repository_path"]).parent.as_posix()))
            file_modules.setdefault(int(row["file_id"]), set()).add(module_id)
            responsibility.append((module_id, row["name"], row["repository_path"], "BUILD_TARGET", "DERIVED"))
        file_rows = rows(connection, "SELECT file_id,repository_path FROM files WHERE generation_id=? ORDER BY repository_path", (generation,))
        for row in file_rows:
            file_id = int(row["file_id"])
            if file_modules.get(file_id):
                continue
            root = row["repository_path"].split("/", 1)[0] if "/" in row["repository_path"] else "."
            module_id = "path:" + stable_id(generation, root)
            connection.execute(
                "INSERT OR IGNORE INTO modules VALUES(?,?,?,?,?,'architecture-normalizer','DERIVED')",
                (module_id, generation, root, "SOURCE_ROOT", root))
            file_modules[file_id] = {module_id}
            responsibility.append((module_id, root, row["repository_path"], "SOURCE_ROOT", "DERIVED"))

        symbol_modules: dict[str, set[str]] = {}
        for row in rows(connection, """SELECT DISTINCT d.symbol_id,r.file_id FROM symbol_definitions d
                JOIN source_regions r USING(region_id) JOIN files f USING(file_id)
                JOIN symbols s ON s.symbol_id=d.symbol_id WHERE s.generation_id=?""", (generation,)):
            symbol_modules.setdefault(row["symbol_id"], set()).update(file_modules.get(int(row["file_id"]), set()))
        edge_counts: dict[tuple[str, str, str], int] = {}
        for row in rows(connection, "SELECT source_symbol_id,target_symbol_id,edge_kind FROM symbol_edges"):
            for source in symbol_modules.get(row["source_symbol_id"], set()):
                for target in symbol_modules.get(row["target_symbol_id"], set()):
                    if source != target:
                        key = (source, target, row["edge_kind"])
                        edge_counts[key] = edge_counts.get(key, 0) + 1
        for (source, target, kind), count in sorted(edge_counts.items()):
            connection.execute("INSERT OR REPLACE INTO module_edges VALUES(?,?,?,'architecture-normalizer',?)",
                               (source, target, kind, count))

        concept_records: list[tuple] = []
        concept_owner_rows: list[tuple[str, str, str]] = []
        owner_by_concept: dict[str, set[str]] = {}
        public_interfaces: list[tuple] = []
        for row in rows(connection, """SELECT s.symbol_id,s.display_name,s.symbol_kind,f.repository_path
                FROM symbols s JOIN symbol_definitions d USING(symbol_id)
                JOIN source_regions r USING(region_id) JOIN files f USING(file_id)
                WHERE s.generation_id=? ORDER BY s.display_name,f.repository_path""", (generation,)):
            concept = row["display_name"]
            modules = symbol_modules.get(row["symbol_id"], set())
            for module_id in sorted(modules):
                owner_by_concept.setdefault(concept, set()).add(module_id)
                concept_owner_rows.append((concept, module_id, row["repository_path"]))
                concept_records.append((concept, "MODULE", module_id, row["repository_path"], "DERIVED"))
            if Path(row["repository_path"]).suffix.lower() in {".h", ".hh", ".hpp", ".hxx", ".inc"}:
                public_interfaces.append((row["display_name"], row["symbol_kind"], row["repository_path"],
                                          ",".join(sorted(modules)) or "-", "DERIVED"))
        connection.executemany(
            "INSERT OR IGNORE INTO concept_owners VALUES(?, 'MODULE', ?, 'DERIVED', 'architecture-normalizer', ?)",
            concept_owner_rows,
        )

        findings: list[tuple[str, str, str, str, str, str]] = []
        for concept, owners in sorted(owner_by_concept.items()):
            if len(owners) > 1:
                findings.append(("AMBIGUOUS_CONCEPT_OWNER", "HIGH", concept,
                                 ",".join(sorted(owners)), "DERIVED", "architecture-normalizer"))
        graph: dict[str, set[str]] = {}
        fanout: dict[str, set[str]] = {}
        for source, target, _ in edge_counts:
            graph.setdefault(source, set()).add(target)
            fanout.setdefault(source, set()).add(target)
        for component in strongly_connected(graph):
            findings.append(("MODULE_CYCLE", "HIGH", component[0], ",".join(component),
                             "DERIVED", "architecture-normalizer"))
        for source, targets in sorted(fanout.items()):
            if len(targets) >= args.high_fanout:
                findings.append(("HIGH_FANOUT_MODULE", "MEDIUM", source,
                                 f"fanout={len(targets)} targets={','.join(sorted(targets))}",
                                 "DERIVED", "architecture-normalizer"))
        for row in rows(connection, "SELECT source_symbol_id,target_value FROM mutation_edges WHERE provider='joern'"):
            modules = symbol_modules.get(row["source_symbol_id"], set())
            if len(modules) > 1:
                findings.append(("CROSS_SUBSYSTEM_WRITE", "HIGH", row["source_symbol_id"],
                                 f"modules={','.join(sorted(modules))} value={row['target_value']}",
                                 "DERIVED", "joern"))
        # A cross-module implementation dependency with neither endpoint in a
        # public header is an evidence-backed failed reasoning-firewall candidate.
        public_modules = {record[3] for record in public_interfaces}
        for source, targets in sorted(graph.items()):
            for target in sorted(targets):
                if not any(source in value or target in value for value in public_modules):
                    findings.append(("REASONING_FIREWALL_CANDIDATE", "MEDIUM", source,
                                     f"private dependency to {target}", "PROPOSED", "architecture-normalizer"))
        for kind, severity, subject, evidence, authority, provider in findings:
            finding_id = stable_id(generation, kind, subject, evidence)
            connection.execute("INSERT OR REPLACE INTO architecture_findings VALUES(?,?,?,?,?,?,?,?)",
                               (finding_id, generation, kind, severity, subject, evidence, authority, provider))
        connection.commit()

        dependencies = [(row["source_module_id"], row["target_module_id"], row["edge_kind"],
                         row["evidence_count"], row["provider"])
                        for row in rows(connection, "SELECT * FROM module_edges ORDER BY source_module_id,target_module_id,edge_kind")]
        tests = [(row["name"], row["repository_path"] or "-", row["build_target"] or "-",
                  row["selector"] or "-", row["provider"])
                 for row in rows(connection, "SELECT t.*,f.repository_path FROM tests t LEFT JOIN files f USING(file_id) WHERE t.generation_id=? ORDER BY t.name", (generation,))]
        write_tsv(output / "responsibility-map.tsv", ("module_id", "module", "path", "basis", "authority"), sorted(set(responsibility)))
        write_tsv(output / "dependency-map.tsv", ("source_module", "target_module", "edge_kind", "evidence_count", "provider"), dependencies)
        write_tsv(output / "ownership-map.tsv", ("concept", "owner_kind", "owner_id", "evidence", "authority"), sorted(set(concept_records)))
        write_tsv(output / "public-interface-map.tsv", ("symbol", "kind", "path", "modules", "authority"), sorted(set(public_interfaces)))
        write_tsv(output / "test-map.tsv", ("test", "path", "build_target", "selector", "provider"), tests)
        write_tsv(output / "concept-owner-map.tsv", ("concept", "owner_kind", "owner_id", "evidence", "authority"), sorted(set(concept_records)))
        write_tsv(output / "findings.tsv", ("finding_kind", "severity", "subject", "evidence", "authority", "provider"), findings)
        summary = {
            "modules": len({record[0] for record in responsibility}),
            "module_edges": len(dependencies), "concepts": len(owner_by_concept),
            "public_interfaces": len(public_interfaces), "tests": len(tests),
            "findings": len(findings), "cycles": sum(1 for f in findings if f[0] == "MODULE_CYCLE"),
            "ambiguous_owners": sum(1 for f in findings if f[0] == "AMBIGUOUS_CONCEPT_OWNER"),
        }
        (output / "summary.json").write_text(json.dumps(summary, sort_keys=True, indent=2) + "\n", encoding="utf-8")
    except Exception:
        connection.rollback()
        raise
    finally:
        connection.close()


def benchmark(args: argparse.Namespace) -> None:
    connection = sqlite3.connect(args.database)
    connection.row_factory = sqlite3.Row
    output_rows: list[tuple] = []
    with Path(args.queries).open(encoding="utf-8", newline="") as stream:
        reader = csv.DictReader(stream, delimiter="\t")
        required = {"benchmark_id", "query", "expected_paths"}
        if not required.issubset(reader.fieldnames or []):
            raise ValueError("benchmark TSV requires benchmark_id, query, expected_paths")
        for record in reader:
            expected = {value.strip() for value in record["expected_paths"].split(",") if value.strip()}
            query = record["query"]
            found = rows(connection, """SELECT DISTINCT f.repository_path FROM symbols s
                JOIN symbol_definitions d USING(symbol_id) JOIN source_regions r USING(region_id)
                JOIN files f USING(file_id) WHERE s.generation_id=? AND
                (s.display_name=? COLLATE NOCASE OR s.symbol_id=? ) ORDER BY f.repository_path LIMIT 50""",
                         (args.generation, query, query))
            returned = {row["repository_path"] for row in found}
            if not returned:
                returned = {row[0] for row in connection.execute(
                    "SELECT repository_path FROM lexical_documents WHERE lexical_documents MATCH ? ORDER BY rank LIMIT 50", (f'"{query}"',))}
            relevant = len(expected & returned)
            context_bytes = sum((Path(args.repository) / path).stat().st_size
                                for path in returned if (Path(args.repository) / path).is_file())
            output_rows.append((record["benchmark_id"], query, ",".join(sorted(expected)),
                                ",".join(sorted(returned)), relevant, len(expected), len(returned), context_bytes))
    connection.close()
    write_tsv(Path(args.output), ("benchmark_id", "query", "expected_paths", "returned_paths",
                                      "relevant_returned", "expected_total", "returned_total", "context_bytes"), output_rows)


def main() -> None:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="operation", required=True)
    normalize = sub.add_parser("normalize")
    normalize.add_argument("--database", required=True)
    normalize.add_argument("--generation", required=True)
    normalize.add_argument("--output", required=True)
    normalize.add_argument("--high-fanout", type=int, default=20)
    bench = sub.add_parser("benchmark")
    bench.add_argument("--database", required=True)
    bench.add_argument("--generation", required=True)
    bench.add_argument("--repository", required=True)
    bench.add_argument("--queries", required=True)
    bench.add_argument("--output", required=True)
    args = parser.parse_args()
    if args.operation == "normalize":
        infer(args)
    else:
        benchmark(args)


if __name__ == "__main__":
    main()
