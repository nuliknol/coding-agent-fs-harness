#!/usr/bin/env python3

"""Import selected Joern CPG evidence into the canonical repository index."""

import argparse
import csv
import hashlib
from pathlib import Path
import sqlite3
import xml.etree.ElementTree as ET


NS = {"g": "http://graphml.graphdrawing.org/xmlns"}


def stable_id(*parts: str) -> str:
    return hashlib.sha256("\0".join(parts).encode()).hexdigest()


def data_map(element: ET.Element, keys: dict[str, str]) -> dict[str, str]:
    return {keys.get(child.attrib.get("key", ""), child.attrib.get("key", "")): child.text or ""
            for child in element.findall("g:data", NS)}


def repository_path(filename: str, repository: Path, source_root: str) -> str:
    """Map Joern's source-root-relative filename to the repository namespace."""
    if not filename or filename.startswith("<"):
        return filename
    path = Path(filename)
    if path.is_absolute():
        try:
            return path.resolve().relative_to(repository).as_posix()
        except ValueError:
            return filename
    normalized = path.as_posix()
    while normalized.startswith("./"):
        normalized = normalized[2:]
    normalized_root = Path(source_root).as_posix().strip("/")
    if normalized_root in {"", "."}:
        return normalized
    if normalized == normalized_root or normalized.startswith(normalized_root + "/"):
        return normalized
    return f"{normalized_root}/{normalized}"


def symbol_for(connection: sqlite3.Connection, generation: str, name: str,
               path: str | None = None) -> str | None:
    short = name.rsplit(".", 1)[-1].split(":", 1)[0]
    params: list[str] = [generation, short]
    clause = ""
    if path:
        clause = " AND EXISTS (SELECT 1 FROM symbol_definitions d JOIN source_regions r USING(region_id) JOIN files f USING(file_id) WHERE d.symbol_id=s.symbol_id AND f.repository_path=?)"
        params.append(path)
    row = connection.execute(
        "SELECT s.symbol_id FROM symbols s WHERE s.generation_id=? AND s.display_name=?" +
        clause + " ORDER BY s.symbol_id LIMIT 1", params).fetchone()
    return str(row[0]) if row else None


def ensure_region(connection: sqlite3.Connection, generation: str, path: str,
                  line: int, label: str, code: str) -> int | None:
    file_row = connection.execute(
        "SELECT file_id FROM files WHERE generation_id=? AND repository_path=?",
        (generation, path)).fetchone()
    if not file_row or line <= 0:
        return None
    connection.execute(
        """INSERT OR IGNORE INTO source_regions
           (file_id,region_kind,name,start_line,start_column,end_line,end_column,content_sha256,provider)
           VALUES(?, 'joern_node', ?, ?, 0, ?, 0, ?, 'joern')""",
        (file_row[0], label, line, line, hashlib.sha256(code.encode()).hexdigest()))
    row = connection.execute(
        """SELECT region_id FROM source_regions WHERE file_id=? AND region_kind='joern_node'
           AND name=? AND start_line=? AND provider='joern'""", (file_row[0], label, line)).fetchone()
    return int(row[0]) if row else None


def import_graphs(args: argparse.Namespace) -> dict[str, int]:
    connection = sqlite3.connect(args.database)
    connection.execute("PRAGMA foreign_keys=ON")
    counts = {"graphs": 0, "calls": 0, "control_flow": 0, "data_flow": 0, "mutations": 0,
              "unresolved_calls": 0}
    classes = {value.strip() for value in args.classes.split(",") if value.strip()}
    repository = Path(args.repository).resolve()
    try:
        connection.execute("BEGIN IMMEDIATE")
        for graph_path in sorted(Path(args.export).rglob("*.xml")):
            if not graph_path.is_file():
                continue
            tree = ET.parse(graph_path)
            root = tree.getroot()
            keys = {key.attrib["id"]: key.attrib.get("attr.name", key.attrib["id"])
                    for key in root.findall("g:key", NS)}
            nodes: dict[str, dict[str, str]] = {}
            for node in root.findall(".//g:node", NS):
                nodes[node.attrib["id"]] = data_map(node, keys)
            methods = [value for value in nodes.values() if value.get("labelV") == "METHOD" and
                       value.get("IS_EXTERNAL", "false") == "false"]
            if not methods:
                continue
            owner = methods[0]
            path = repository_path(owner.get("FILENAME", ""), repository, args.source_root)
            owner_name = owner.get("NAME", owner.get("FULL_NAME", ""))
            owner_symbol = symbol_for(connection, args.generation, owner_name, path)
            counts["graphs"] += 1
            regions: dict[str, int | None] = {}
            for node_id, value in nodes.items():
                line_text = value.get("LINE_NUMBER", "0")
                line = int(line_text) if line_text.isdigit() else 0
                regions[node_id] = ensure_region(connection, args.generation, path, line,
                                                  value.get("labelV", "NODE"), value.get("CODE", ""))
                if value.get("labelV") != "CALL" or owner_symbol is None:
                    continue
                target_name = value.get("METHOD_FULL_NAME", "")
                if "call" in classes and target_name and not target_name.startswith("<operator>"):
                    target = symbol_for(connection, args.generation, target_name)
                    if target:
                        connection.execute(
                            """INSERT OR IGNORE INTO call_edges
                               (caller_symbol_id,callee_symbol_id,evidence_region_id,provider,confidence)
                               VALUES(?,?,?,'joern','DERIVED')""",
                            (owner_symbol, target, regions[node_id]))
                        counts["calls"] += 1
                    else:
                        counts["unresolved_calls"] += 1
                if "mutation" in classes and ("assignment" in target_name.lower() or
                                                "increment" in target_name.lower() or
                                                "decrement" in target_name.lower()):
                    connection.execute(
                        """INSERT OR IGNORE INTO mutation_edges
                           (source_symbol_id,target_symbol_id,target_value,evidence_region_id,provider,confidence)
                           VALUES(?,?,?,?,'joern','DERIVED')""",
                        (owner_symbol, owner_symbol, value.get("CODE", target_name), regions[node_id]))
                    counts["mutations"] += 1
            for edge in root.findall(".//g:edge", NS):
                edge_data = data_map(edge, keys)
                label = edge_data.get("labelE", "")
                source_region = regions.get(edge.attrib.get("source", ""))
                target_region = regions.get(edge.attrib.get("target", ""))
                if source_region is None or target_region is None:
                    continue
                if "control-flow" in classes and label in {"CFG", "CDG", "DOMINATE", "POST_DOMINATE"}:
                    connection.execute(
                        "INSERT OR IGNORE INTO control_flow_edges VALUES(?,?,?,'joern')",
                        (source_region, target_region, label))
                    counts["control_flow"] += 1
                if "data-flow" in classes and label == "REACHING_DEF":
                    connection.execute(
                        "INSERT OR IGNORE INTO data_flow_edges VALUES(?,?,?,?, 'joern')",
                        (source_region, target_region, edge_data.get("property"), label))
                    counts["data_flow"] += 1
        connection.execute(
            """INSERT OR REPLACE INTO provider_runs
               (provider,generation_id,provider_version,fingerprint,status,evidence_path,recorded_at)
               VALUES('joern',?,?,?,?,?,datetime('now'))""",
            (args.generation, args.version, args.fingerprint, "READY", str(Path(args.export).resolve())))
        connection.commit()
    except Exception:
        connection.rollback()
        raise
    finally:
        connection.close()
    return counts


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--database", required=True)
    parser.add_argument("--generation", required=True)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--source-root", required=True)
    parser.add_argument("--export", required=True)
    parser.add_argument("--classes", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--fingerprint", required=True)
    parser.add_argument("--report", required=True)
    args = parser.parse_args()
    counts = import_graphs(args)
    with Path(args.report).open("w", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream, delimiter="\t", lineterminator="\n")
        writer.writerow(("metric", "value"))
        writer.writerows(sorted(counts.items()))


if __name__ == "__main__":
    main()
