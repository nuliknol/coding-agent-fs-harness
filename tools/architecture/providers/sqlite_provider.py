"""SQLite/SCIP architecture evidence adapter."""

from __future__ import annotations

from collections import defaultdict
from pathlib import Path
import sqlite3

from architecture.model import (
    ArchitectureSnapshot, ConceptOwner, Dependency, Finding, Module,
    PublicInterface, TestRecord, stable_id,
)


def _rows(connection: sqlite3.Connection, query: str, parameters=()) -> list[sqlite3.Row]:
    return connection.execute(query, parameters).fetchall()


class SQLiteProvider:
    provider = "architecture-normalizer"

    def __init__(self, database: Path, generation: str):
        self.database = database
        self.generation = generation
        self.symbol_modules: dict[str, set[str]] = {}

    def collect(self) -> ArchitectureSnapshot:
        snapshot = ArchitectureSnapshot(self.generation)
        connection = sqlite3.connect(self.database)
        connection.row_factory = sqlite3.Row
        file_modules: dict[int, set[str]] = defaultdict(set)
        try:
            targets = _rows(connection, """
                SELECT bt.target_id,bt.name,bt.target_kind,bt.definition_path,
                       btf.file_id,f.repository_path
                FROM build_targets bt JOIN build_target_files btf USING(target_id)
                JOIN files f USING(file_id)
                WHERE bt.generation_id=? ORDER BY bt.name,f.repository_path
                """, (self.generation,))
            for row in targets:
                module_id = "build:" + row["target_id"]
                snapshot.modules.add(Module(
                    module_id, row["name"], row["definition_path"] or Path(row["repository_path"]).parent.as_posix(),
                    row["target_kind"] or "BUILD_TARGET", provider=self.provider,
                ))
                file_modules[int(row["file_id"])].add(module_id)
            files = _rows(connection,
                          "SELECT file_id,repository_path FROM files WHERE generation_id=? ORDER BY repository_path",
                          (self.generation,))
            for row in files:
                file_id = int(row["file_id"])
                if file_modules[file_id]:
                    continue
                root = row["repository_path"].split("/", 1)[0] if "/" in row["repository_path"] else "."
                module_id = "path:" + stable_id(self.generation, root)
                snapshot.modules.add(Module(module_id, root, root, "SOURCE_ROOT", provider=self.provider))
                file_modules[file_id].add(module_id)

            symbol_modules: dict[str, set[str]] = defaultdict(set)
            definitions = _rows(connection, """
                SELECT DISTINCT s.symbol_id,s.display_name,s.symbol_kind,r.file_id,f.repository_path
                FROM symbols s JOIN symbol_definitions d USING(symbol_id)
                JOIN source_regions r USING(region_id) JOIN files f USING(file_id)
                WHERE s.generation_id=? ORDER BY s.symbol_id,f.repository_path
                """, (self.generation,))
            for row in definitions:
                modules = file_modules[int(row["file_id"])]
                symbol_modules[row["symbol_id"]].update(modules)
                for module_id in modules:
                    snapshot.concept_owners.add(ConceptOwner(
                        "symbol:" + row["symbol_id"], "MODULE", module_id,
                        row["repository_path"], provider=self.provider,
                    ))
                    if Path(row["repository_path"]).suffix.lower() in {".h", ".hh", ".hpp", ".hxx", ".inc"}:
                        snapshot.public_interfaces.add(PublicInterface(
                            row["display_name"], row["symbol_kind"], row["repository_path"], module_id,
                            provider=self.provider,
                        ))
            self.symbol_modules = dict(symbol_modules)

            counts: dict[tuple[str, str, str], int] = defaultdict(int)
            for row in _rows(connection, "SELECT source_symbol_id,target_symbol_id,edge_kind FROM symbol_edges"):
                for source in symbol_modules.get(row["source_symbol_id"], set()):
                    for target in symbol_modules.get(row["target_symbol_id"], set()):
                        if source != target:
                            counts[(source, target, row["edge_kind"])] += 1
            for (source, target, kind), count in counts.items():
                snapshot.dependencies.add(Dependency(source, target, kind, count, self.provider))

            for row in _rows(connection, """
                SELECT t.name,f.repository_path,t.build_target,t.selector,t.provider
                FROM tests t LEFT JOIN files f USING(file_id)
                WHERE t.generation_id=? ORDER BY t.name
                """, (self.generation,)):
                snapshot.tests.add(TestRecord(
                    row["name"], row["repository_path"] or "-", row["build_target"] or "-",
                    row["selector"] or "-", row["provider"],
                ))

            for row in _rows(connection, """
                SELECT source_symbol_id,target_symbol_id,target_value
                FROM mutation_edges WHERE provider='joern'
                """):
                source_modules = symbol_modules.get(row["source_symbol_id"], set())
                target_modules = symbol_modules.get(row["target_symbol_id"], set()) if row["target_symbol_id"] else set()
                cross = sorted((source, target) for source in source_modules for target in target_modules if source != target)
                for source, target in cross:
                    snapshot.findings.add(Finding(
                        "CROSS_SUBSYSTEM_WRITE", "HIGH", row["source_symbol_id"],
                        f"source={source} target={target} value={row['target_value'] or '-'}",
                        "DERIVED", "joern",
                    ))
        finally:
            connection.close()
        return snapshot

    def persist(self, snapshot: ArchitectureSnapshot) -> None:
        connection = sqlite3.connect(self.database)
        try:
            connection.execute("PRAGMA foreign_keys=ON")
            connection.execute("BEGIN IMMEDIATE")
            derived_ids = [row[0] for row in connection.execute(
                "SELECT module_id FROM modules WHERE generation_id=? AND authority='DERIVED'",
                (self.generation,)).fetchall()]
            if derived_ids:
                placeholders = ",".join("?" for _ in derived_ids)
                connection.execute(
                    f"DELETE FROM module_edges WHERE source_module_id IN ({placeholders}) OR target_module_id IN ({placeholders})",
                    (*derived_ids, *derived_ids),
                )
            connection.execute("DELETE FROM modules WHERE generation_id=? AND authority='DERIVED'", (self.generation,))
            connection.execute("DELETE FROM architecture_findings WHERE generation_id=?", (self.generation,))
            connection.execute(
                "DELETE FROM concept_owners WHERE authority='DERIVED' AND provider IN "
                "('architecture-normalizer','bash-static','python-ast','architecture-inference')")
            connection.executemany(
                "INSERT OR REPLACE INTO modules(module_id,generation_id,name,module_kind,root_path,provider,authority) VALUES(?,?,?,?,?,?,?)",
                ((m.module_id, self.generation, m.name, m.kind, m.path, m.provider, m.authority)
                 for m in sorted(snapshot.modules)),
            )
            connection.executemany(
                "INSERT OR REPLACE INTO module_edges(source_module_id,target_module_id,edge_kind,provider,evidence_count) VALUES(?,?,?,?,?)",
                ((d.source, d.target, d.kind, d.provider, d.evidence_count)
                 for d in sorted(snapshot.dependencies)),
            )
            connection.executemany(
                "INSERT OR REPLACE INTO concept_owners(concept_id,owner_kind,owner_id,authority,provider,evidence) VALUES(?,?,?,?,?,?)",
                ((c.concept, c.owner_kind, c.owner_id, c.authority, c.provider, c.evidence)
                 for c in sorted(snapshot.concept_owners)),
            )
            connection.executemany(
                "INSERT OR REPLACE INTO architecture_findings(finding_id,generation_id,finding_kind,severity,subject_id,evidence,authority,provider) VALUES(?,?,?,?,?,?,?,?)",
                ((stable_id(self.generation, f.kind, f.subject, f.evidence), self.generation,
                  f.kind, f.severity, f.subject, f.evidence, f.authority, f.provider)
                 for f in sorted(snapshot.findings)),
            )
            connection.commit()
        except Exception:
            connection.rollback()
            raise
        finally:
            connection.close()
