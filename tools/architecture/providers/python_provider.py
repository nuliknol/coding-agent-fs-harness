"""Python AST architecture evidence provider."""

from __future__ import annotations

import ast
from pathlib import Path
import subprocess

from architecture.model import (
    ArchitectureSnapshot, ConceptOwner, Dependency, Finding, Module,
    PublicInterface, StateAccess, TestRecord, stable_id,
)


def _tracked_python(repository: Path) -> list[Path]:
    result = subprocess.run(["git", "-C", str(repository), "ls-files", "-z", "*.py"],
                            check=False, stdout=subprocess.PIPE)
    if result.returncode == 0:
        return [repository / name for name in result.stdout.decode().split("\0") if name]
    return sorted(repository.rglob("*.py"))


def _module_name(path: str) -> str:
    value = path[:-3] if path.endswith(".py") else path
    return value.replace("/", ".").removesuffix(".__init__")


class PythonProvider:
    provider = "python-ast"

    def __init__(self, repository: Path, generation: str):
        self.repository = repository.resolve()
        self.generation = generation

    def collect(self) -> ArchitectureSnapshot:
        snapshot = ArchitectureSnapshot(self.generation)
        paths = [path.relative_to(self.repository).as_posix() for path in _tracked_python(self.repository)]
        module_ids = {path: "python:" + stable_id(self.generation, path) for path in paths}
        names = {_module_name(path): path for path in paths}
        for path in sorted(paths):
            absolute = self.repository / path
            text = absolute.read_text(encoding="utf-8", errors="replace")
            module_id = module_ids[path]
            kind = "PYTHON_TEST" if Path(path).name.startswith("test_") or path.startswith("tests/") else "PYTHON_MODULE"
            snapshot.modules.add(Module(module_id, _module_name(path), path, kind, provider=self.provider))
            if text.count("\n") + 1 >= 1000:
                snapshot.findings.add(Finding(
                    "LARGE_MODULE", "MEDIUM", module_id,
                    f"path={path} lines={text.count(chr(10)) + 1}", "DERIVED", self.provider,
                ))
            if kind == "PYTHON_TEST":
                snapshot.tests.add(TestRecord(Path(path).name, path, selector=f"python3 -m unittest {path}", provider=self.provider))
            try:
                tree = ast.parse(text, filename=path)
            except SyntaxError as error:
                snapshot.findings.add(Finding(
                    "PROVIDER_PARSE_FAILURE", "MEDIUM", module_id,
                    f"{path}:{error.lineno or 0}:{error.msg}", "DERIVED", self.provider,
                ))
                continue
            for node in ast.walk(tree):
                if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
                    kind_name = "PYTHON_CLASS" if isinstance(node, ast.ClassDef) else "PYTHON_FUNCTION"
                    snapshot.concept_owners.add(ConceptOwner(
                        f"python-symbol:{_module_name(path)}.{node.name}", "MODULE", module_id,
                        f"{path}:{node.lineno}", provider=self.provider,
                    ))
                    if not node.name.startswith("_"):
                        snapshot.public_interfaces.add(PublicInterface(
                            node.name, kind_name, path, module_id, provider=self.provider,
                        ))
                elif isinstance(node, (ast.Import, ast.ImportFrom)):
                    imports = [alias.name for alias in node.names] if isinstance(node, ast.Import) else [node.module or ""]
                    for imported in imports:
                        candidates = [name for name in names if imported == name or imported.startswith(name + ".")]
                        if candidates:
                            target = names[max(candidates, key=len)]
                            if target != path:
                                snapshot.dependencies.add(Dependency(
                                    module_id, module_ids[target], "IMPORTS", 1, self.provider,
                                ))
                elif isinstance(node, ast.Call):
                    name = ""
                    if isinstance(node.func, ast.Attribute):
                        name = node.func.attr
                    elif isinstance(node.func, ast.Name):
                        name = node.func.id
                    if name in {"write_text", "write_bytes", "replace", "rename", "unlink"}:
                        snapshot.state_accesses.add(StateAccess(
                            "FILESYSTEM", name, module_id, "WRITE", f"{path}:{node.lineno}", provider=self.provider,
                        ))
        return snapshot

