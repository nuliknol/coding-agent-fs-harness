#!/usr/bin/env python3

"""Project normative architecture records onto an immutable derived index."""

import argparse
import csv
from pathlib import Path
import sqlite3


def split(value: str) -> list[str]:
    return [part.strip() for part in value.split(",") if part.strip() not in {"", "-"}]


def read(path: Path) -> list[dict[str, str]]:
    if not path.is_file():
        return []
    with path.open(encoding="utf-8", errors="replace", newline="") as stream:
        return list(csv.DictReader(stream, delimiter="\t"))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--database", required=True)
    parser.add_argument("--generation", required=True)
    parser.add_argument("--architecture", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    architecture = Path(args.architecture)
    connection = sqlite3.connect(args.database)
    connection.row_factory = sqlite3.Row
    symbols: dict[str, set[str]] = {}
    symbol_paths: dict[str, set[str]] = {}
    for row in connection.execute("""SELECT s.display_name,s.symbol_id,f.repository_path
            FROM symbols s LEFT JOIN symbol_definitions d USING(symbol_id)
            LEFT JOIN source_regions r USING(region_id) LEFT JOIN files f USING(file_id)
            WHERE s.generation_id=?""", (args.generation,)):
        symbols.setdefault(row["display_name"], set()).add(row["symbol_id"])
        if row["repository_path"]:
            symbol_paths.setdefault(row["symbol_id"], set()).add(row["repository_path"])
    modules = list(connection.execute(
        "SELECT module_id,root_path FROM modules WHERE generation_id=?", (args.generation,)))

    records: list[tuple[str, ...]] = []

    def project(kind: str, identifier: str, authority: str, scopes: list[str], names: list[str], nodes: list[str]) -> None:
        matched_symbols: set[str] = set()
        matched_modules: set[str] = set()
        for name in names:
            matched_symbols.update(symbols.get(name, set()))
        for symbol_id in matched_symbols:
            for path in symbol_paths.get(symbol_id, set()):
                for module in modules:
                    root = module["root_path"] or "."
                    if root == "." or path == root or path.startswith(root.rstrip("/") + "/"):
                        matched_modules.add(module["module_id"])
        for scope in scopes:
            normalized = scope.rstrip("/")
            for module in modules:
                root = (module["root_path"] or ".").rstrip("/")
                if root == "." or normalized == root or normalized.startswith(root + "/") or root.startswith(normalized + "/"):
                    matched_modules.add(module["module_id"])
            for symbol_id, paths in symbol_paths.items():
                if any(path == normalized or path.startswith(normalized + "/") for path in paths):
                    matched_symbols.add(symbol_id)
        unresolved = []
        unresolved.extend(f"symbol:{name}" for name in names if name not in symbols)
        if not scopes and not names:
            unresolved.append("no-structural-seed")
        records.append((kind, identifier, authority or "NORMATIVE", ",".join(scopes) or "-",
                        ",".join(names) or "-", ",".join(nodes) or "-",
                        ",".join(sorted(matched_symbols)) or "-",
                        ",".join(sorted(matched_modules)) or "-",
                        ",".join(unresolved) or "-"))

    for row in read(architecture / "invariants.tsv"):
        project("INVARIANT", row.get("invariant_id", "-"), row.get("authority", "NORMATIVE"),
                split(row.get("scope", "")), [], split(row.get("affected_nodes", "")))
    for row in read(architecture / "decisions.tsv"):
        project("DECISION", row.get("decision_id", "-"), "NORMATIVE", [],
                split(row.get("affected_interfaces", "")), split(row.get("producer_node", "")))
    for row in read(architecture / "edges.tsv"):
        artifacts = [value for value in split(row.get("contract_artifact", "")) if not value.startswith("decision:")]
        project("EDGE", row.get("edge_id", "-"), "NORMATIVE", artifacts,
                split(row.get("public_symbols", "")),
                split(row.get("producer_node", "")) + split(row.get("consumer_node", "")))
    for row in read(architecture / "node-bindings.tsv"):
        project("NODE_BINDING", row.get("node_id", "-"), "NORMATIVE", [], [], [row.get("node_id", "-")])

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream, delimiter="\t", lineterminator="\n")
        writer.writerow(("record_kind", "record_id", "authority", "declared_scopes", "declared_symbols",
                         "affected_nodes", "matched_symbol_ids", "matched_module_ids", "unresolved"))
        writer.writerows(sorted(records))
    connection.close()


if __name__ == "__main__":
    main()
