#!/usr/bin/env python3

"""Export a compact deterministic repository architecture slice for Sol."""

import argparse
from pathlib import Path
import sqlite3


def rows(connection: sqlite3.Connection, query: str) -> list[sqlite3.Row]:
    return connection.execute(query).fetchall()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--database", required=True)
    parser.add_argument("--generation", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    connection = sqlite3.connect(args.database)
    connection.row_factory = sqlite3.Row
    counts = {
        table: connection.execute(f"SELECT count(*) FROM {table}").fetchone()[0]
        for table in ("files", "symbols", "symbol_edges", "tests", "build_targets", "build_target_files")
    }
    targets = rows(connection, """
        SELECT bt.name, bt.target_kind, COALESCE(bt.definition_path, '-') AS definition_path,
               count(DISTINCT btf.file_id) AS source_count,
               (SELECT group_concat(repository_path, ',') FROM (
                    SELECT DISTINCT f2.repository_path AS repository_path
                    FROM build_target_files btf2
                    JOIN files f2 ON f2.file_id=btf2.file_id
                    WHERE btf2.target_id=bt.target_id
                    ORDER BY f2.repository_path
                )) AS sources
        FROM build_targets bt
        LEFT JOIN build_target_files btf ON btf.target_id=bt.target_id
        LEFT JOIN files f ON f.file_id=btf.file_id
        GROUP BY bt.target_id
        ORDER BY bt.name LIMIT 128
    """)
    roots = rows(connection, """
        SELECT CASE WHEN instr(repository_path, '/') > 0
                    THEN substr(repository_path, 1, instr(repository_path, '/') - 1)
                    ELSE '.' END AS source_root,
               count(*) AS file_count
        FROM files GROUP BY source_root ORDER BY file_count DESC, source_root LIMIT 32
    """)
    fanout = rows(connection, """
        SELECT s.display_name, COALESCE(min(f.repository_path), '-') AS repository_path,
               count(DISTINCT e.target_symbol_id) AS outgoing_edges
        FROM symbol_edges e
        JOIN symbols s ON s.symbol_id=e.source_symbol_id
        LEFT JOIN symbol_definitions d ON d.symbol_id=s.symbol_id
        LEFT JOIN source_regions r ON r.region_id=d.region_id
        LEFT JOIN files f ON f.file_id=r.file_id
        GROUP BY s.symbol_id
        ORDER BY outgoing_edges DESC, s.display_name LIMIT 24
    """)
    interfaces = rows(connection, """
        SELECT DISTINCT display_name, repository_path FROM (
            SELECT s.display_name AS display_name, f.repository_path AS repository_path
            FROM symbols s
            JOIN symbol_definitions d ON d.symbol_id=s.symbol_id
            JOIN source_regions r ON r.region_id=d.region_id
            JOIN files f ON f.file_id=r.file_id
            WHERE f.repository_path LIKE 'include/%' OR f.repository_path LIKE '%/include/%'
            UNION
            SELECT s.display_name AS display_name, f.repository_path AS repository_path
            FROM symbols s
            JOIN symbol_references x ON x.symbol_id=s.symbol_id
            JOIN source_regions r ON r.region_id=x.region_id
            JOIN files f ON f.file_id=r.file_id
            WHERE f.repository_path LIKE 'include/%' OR f.repository_path LIKE '%/include/%'
        )
        WHERE display_name GLOB '*[A-Za-z_]*' AND display_name NOT LIKE '<file>%'
        ORDER BY repository_path, display_name LIMIT 64
    """)
    tests = rows(connection, """
        SELECT t.name, COALESCE(t.build_target, '-') AS build_target,
               COALESCE(f.repository_path, '-') AS repository_path,
               count(DISTINCT x.symbol_id) AS covered_symbols
        FROM tests t
        LEFT JOIN files f ON f.file_id=t.file_id
        LEFT JOIN test_symbol_edges x ON x.test_id=t.test_id
        GROUP BY t.test_id
        ORDER BY covered_symbols DESC, t.name LIMIT 64
    """)
    modules = rows(connection, """
        SELECT m.name,m.module_kind,COALESCE(m.root_path,'-') root_path,m.authority,
               count(DISTINCT e.target_module_id) fanout
        FROM modules m LEFT JOIN module_edges e ON e.source_module_id=m.module_id
        GROUP BY m.module_id ORDER BY fanout DESC,m.name LIMIT 64
    """)
    module_edges = rows(connection, """
        SELECT s.name source,t.name target,e.edge_kind,e.evidence_count,e.provider
        FROM module_edges e JOIN modules s ON s.module_id=e.source_module_id
        JOIN modules t ON t.module_id=e.target_module_id
        ORDER BY e.evidence_count DESC,s.name,t.name LIMIT 96
    """)
    findings = rows(connection, """
        SELECT finding_kind,severity,subject_id,evidence,authority,provider
        FROM architecture_findings ORDER BY severity,finding_kind,subject_id LIMIT 64
    """)
    providers = rows(connection, """
        SELECT provider,status,provider_version FROM provider_runs ORDER BY provider
    """)
    lines = [
        "# Repository Architecture Slice", "", f"Index-Generation: {args.generation}", "",
        "This is deterministic navigation evidence, not normative architecture authority.", "",
        "## Coverage", "",
    ]
    lines.extend(f"- {name}: {value}" for name, value in sorted(counts.items()))
    lines.extend(("", "## Build ownership", ""))
    if targets:
        for row in targets:
            lines.append(
                f"- `{row['name']}` ({row['target_kind']}), definition `{row['definition_path']}`, "
                f"sources={row['source_count']}: {row['sources'] or '-'}")
    else:
        lines.append("- No build targets were inferred from the selected compilation database.")
    lines.extend(("", "## Derived module graph", ""))
    lines.extend(f"- `{row['name']}` ({row['module_kind']}, {row['authority']}) root `{row['root_path']}`; fanout={row['fanout']}"
                 for row in modules)
    if not modules:
        lines.append("- NONE")
    lines.extend(("", "### Module dependencies", ""))
    lines.extend(f"- `{row['source']}` -> `{row['target']}`: {row['edge_kind']} evidence={row['evidence_count']} ({row['provider']})"
                 for row in module_edges)
    if not module_edges:
        lines.append("- NONE")
    lines.extend(("", "## Source roots", ""))
    lines.extend(f"- `{row['source_root']}`: {row['file_count']} indexed files" for row in roots)
    lines.extend(("", "## High-fanout structural symbols", ""))
    lines.extend(
        f"- `{row['display_name']}` at `{row['repository_path']}`: {row['outgoing_edges']} outgoing edges"
        for row in fanout
    )
    if not fanout:
        lines.append("- NONE")
    lines.extend(("", "## Public interface candidates", ""))
    lines.extend(f"- `{row['display_name']}` — `{row['repository_path']}`" for row in interfaces)
    if not interfaces:
        lines.append("- NONE")
    lines.extend(("", "## Focused test map", ""))
    lines.extend(
        f"- `{row['name']}` target `{row['build_target']}` at `{row['repository_path']}`; "
        f"covered-symbols={row['covered_symbols']}" for row in tests
    )
    if not tests:
        lines.append("- NONE")
    lines.extend(("", "## Architecture findings requiring targeted verification", ""))
    lines.extend(f"- [{row['severity']}] {row['finding_kind']} `{row['subject_id']}`: {row['evidence']} ({row['authority']}, {row['provider']})"
                 for row in findings)
    if not findings:
        lines.append("- NONE")
    lines.extend(("", "## Evidence-provider coverage", ""))
    lines.extend(f"- `{row['provider']}`: {row['status']} — {row['provider_version']}" for row in providers)
    if not providers:
        lines.append("- NONE")
    lines.append("")
    Path(args.output).write_text("\n".join(lines), encoding="utf-8")
    connection.close()


if __name__ == "__main__":
    main()
