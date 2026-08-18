"""Deterministic, conservative Bash architecture evidence provider."""

from __future__ import annotations

from collections import Counter, defaultdict
from pathlib import Path
import re
import subprocess

from architecture.model import (
    ArchitectureSnapshot, ConceptOwner, Dependency, Finding, Module,
    PublicInterface, StateAccess, TestRecord, stable_id,
)


FUNCTION_RE = re.compile(r"^\s*(?:function\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*\(\s*\)\s*(?:\{|$)")
SOURCE_RE = re.compile(r"^\s*(?:source|\.)\s+(.+?)\s*(?:#.*)?$")
TOKEN_RE = re.compile(r"\b([A-Za-z_][A-Za-z0-9_]*)\b")
CONFIG_RE = re.compile(r"\b(HARNESS_[A-Z0-9_]+)\b")
STATE_FRAGMENT_RE = re.compile(r"(?:control|tasks|running|results|archive|sessions|logs)/[A-Za-z0-9_.$(){}'\"/-]+")
WRITE_RE = re.compile(r"(?:^|\s)(?:>|>>|mv|install|cp|rm|touch|mkdir)\b|(?:>|>>)\s*[^&]")


def _tracked_files(repository: Path) -> list[Path]:
    result = subprocess.run(
        ["git", "-C", str(repository), "ls-files", "-z"], check=False,
        stdout=subprocess.PIPE,
    )
    if result.returncode == 0:
        names = [name for name in result.stdout.decode(errors="surrogateescape").split("\0") if name]
        return [repository / name for name in names]
    return sorted(path for path in repository.rglob("*") if path.is_file() and ".git" not in path.parts)


def _is_bash(path: Path) -> bool:
    if path.suffix == ".sh":
        return True
    try:
        with path.open("rb") as stream:
            first = stream.readline(256)
    except OSError:
        return False
    return first.startswith(b"#!") and (b"bash" in first or b"/sh" in first or b" env sh" in first)


def _resolve_source(raw: str, current: str, known: set[str]) -> str | None:
    value = raw.strip().strip("'").strip('"')
    filename_match = re.search(r"([A-Za-z0-9_.-]+\.sh)", value)
    if not filename_match:
        return None
    filename = filename_match.group(1)
    candidates = [path for path in known if path.endswith("/" + filename) or path == filename]
    if len(candidates) == 1:
        return candidates[0]
    current_parent = Path(current).parent
    relative = (current_parent / value.replace("$SCRIPT_DIR/", "")).as_posix()
    normalized = Path(relative).as_posix()
    return normalized if normalized in known else None


class BashProvider:
    provider = "bash-static"

    def __init__(self, repository: Path, generation: str):
        self.repository = repository.resolve()
        self.generation = generation

    def collect(self) -> ArchitectureSnapshot:
        snapshot = ArchitectureSnapshot(self.generation)
        files = [path for path in _tracked_files(self.repository) if _is_bash(path)]
        relative = {path.relative_to(self.repository).as_posix(): path for path in files}
        module_ids = {
            path: "shell:" + stable_id(self.generation, path) for path in relative
        }
        definitions: dict[str, list[tuple[str, int]]] = defaultdict(list)
        texts: dict[str, list[str]] = {}

        for path, absolute in sorted(relative.items()):
            lines = absolute.read_text(encoding="utf-8", errors="replace").splitlines()
            texts[path] = lines
            kind = "SHELL_LIBRARY" if path.startswith("lib/") else "SHELL_TEST" if path.startswith("tests/") else "SHELL_COMMAND"
            module_id = module_ids[path]
            snapshot.modules.add(Module(module_id, path, path, kind, provider=self.provider))
            if len(lines) >= 1000:
                snapshot.findings.add(Finding(
                    "LARGE_MODULE", "MEDIUM", module_id, f"path={path} lines={len(lines)}",
                    "DERIVED", self.provider,
                ))
            if kind == "SHELL_TEST":
                snapshot.tests.add(TestRecord(Path(path).name, path, selector=f"bash {path}", provider=self.provider))
            for number, line in enumerate(lines, 1):
                match = FUNCTION_RE.match(line)
                if not match:
                    continue
                name = match.group(1)
                definitions[name].append((path, number))
                concept = (f"shell-function:{name}" if kind == "SHELL_LIBRARY"
                           else f"shell-local:{path}:{name}")
                evidence = f"{path}:{number}"
                snapshot.concept_owners.add(ConceptOwner(
                    concept, "MODULE", module_id, evidence, provider=self.provider,
                ))
                if kind == "SHELL_LIBRARY":
                    snapshot.public_interfaces.add(PublicInterface(
                        name, "SHELL_FUNCTION", path, module_id, provider=self.provider,
                    ))

        known = set(relative)
        for path, lines in sorted(texts.items()):
            module_id = module_ids[path]
            call_counts: Counter[str] = Counter()
            for number, line in enumerate(lines, 1):
                source = SOURCE_RE.match(line)
                if source:
                    target_path = _resolve_source(source.group(1), path, known)
                    if target_path and target_path != path:
                        snapshot.dependencies.add(Dependency(
                            module_id, module_ids[target_path], "SOURCES", 1, self.provider,
                        ))
                if not FUNCTION_RE.match(line) and not line.lstrip().startswith("#"):
                    for token in TOKEN_RE.findall(line):
                        if token in definitions:
                            call_counts[token] += 1
                config_matches = CONFIG_RE.findall(line)
                for config in sorted(set(config_matches)):
                    access = "WRITE" if re.search(rf"(?:export\s+)?{re.escape(config)}=", line) else "READ"
                    snapshot.state_accesses.add(StateAccess(
                        "CONFIGURATION", config, module_id, access, f"{path}:{number}", provider=self.provider,
                    ))
                if WRITE_RE.search(line):
                    for fragment in STATE_FRAGMENT_RE.findall(line):
                        state_id = fragment.strip("'\";)")
                        snapshot.state_accesses.add(StateAccess(
                            "PROJECT_ARTIFACT", state_id, module_id, "WRITE", f"{path}:{number}",
                            provider=self.provider,
                        ))
            for function, count in sorted(call_counts.items()):
                owners = definitions[function]
                if len(owners) != 1:
                    continue
                target_path, _ = owners[0]
                if target_path != path:
                    snapshot.dependencies.add(Dependency(
                        module_id, module_ids[target_path], "CALLS", count, self.provider,
                    ))

        return snapshot
