#!/usr/bin/env python3

"""Extract and validate a patch-only worker proposal before applying it."""

import argparse
from pathlib import Path
import re
import subprocess


DIFF_BLOCK = re.compile(r"```(?:diff|patch)\s*\n(.*?)```", re.DOTALL | re.IGNORECASE)
HUNK_HEADER = re.compile(
    r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@(.*)$")
BINARY_SUFFIXES = {".a", ".bin", ".class", ".dll", ".dylib", ".exe", ".o", ".obj", ".pyc", ".so"}


def split_scope(value: str) -> list[str]:
    return [item.strip().rstrip("/") for item in value.split(",")
            if item.strip() not in ("", "-", "NONE")]


def allowed(path: str, scopes: list[str]) -> bool:
    return any(path == scope or path.startswith(scope + "/") for scope in scopes)


def extract(response: Path) -> str:
    text = response.read_text(encoding="utf-8", errors="replace")
    blocks = DIFF_BLOCK.findall(text)
    if len(blocks) != 1:
        raise ValueError("patch-only response must contain exactly one fenced diff/patch block")
    patch = blocks[0]
    if "GIT binary patch" in patch or "Binary files " in patch:
        raise ValueError("binary patches are prohibited")
    if re.search(r"^(?:new file mode|old mode|new mode) 120000$", patch, re.MULTILINE):
        raise ValueError("symlink patches are prohibited")
    if not patch.startswith("diff --git "):
        raise ValueError("proposal is not a Git unified patch")
    return normalize_hunk_counts(patch if patch.endswith("\n") else patch + "\n")


def normalize_hunk_counts(patch: str) -> str:
    """Repair only unified-diff hunk cardinalities from their literal bodies.

    Small models commonly emit the correct before/after lines with an off-by-one
    count in the @@ header.  The header counts are redundant framing metadata;
    deriving them deterministically does not invent or alter a source change.
    Git still validates the resulting context, baseline, paths, and whitespace.
    """
    lines = patch.splitlines(keepends=True)
    normalized = list(lines)
    index = 0
    while index < len(lines):
        header = lines[index].rstrip("\r\n")
        match = HUNK_HEADER.fullmatch(header)
        if match is None:
            index += 1
            continue
        end = index + 1
        old_count = 0
        new_count = 0
        while end < len(lines):
            body = lines[end]
            if body.startswith(("@@ ", "diff --git ")):
                break
            if body.startswith("\\ No newline at end of file"):
                end += 1
                continue
            if not body.startswith((" ", "+", "-")):
                break
            if body.startswith((" ", "-")):
                old_count += 1
            if body.startswith((" ", "+")):
                new_count += 1
            end += 1
        old_start, _, new_start, _, suffix = match.groups()
        normalized[index] = (
            f"@@ -{old_start},{old_count} +{new_start},{new_count} @@{suffix}\n")
        index = end
    return "".join(normalized)


def patch_paths(repository: Path, patch: Path) -> list[str]:
    result = subprocess.run(["git", "-C", str(repository), "apply", "--numstat", str(patch)],
                            check=False, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode:
        raise ValueError("git apply --numstat rejected the proposal: " + result.stderr.strip())
    paths: list[str] = []
    for line in result.stdout.splitlines():
        fields = line.split("\t")
        if len(fields) != 3:
            raise ValueError("unexpected numstat row")
        if fields[0] == "-" or fields[1] == "-":
            raise ValueError("binary patch statistics are prohibited")
        path = fields[2]
        if " => " in path:
            raise ValueError("renames are prohibited in patch-only mode")
        candidate = Path(path)
        if candidate.is_absolute() or ".." in candidate.parts:
            raise ValueError(f"unsafe patch path: {path}")
        paths.append(candidate.as_posix())
    if not paths:
        raise ValueError("patch proposes no file changes")
    return sorted(set(paths))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repository", required=True)
    parser.add_argument("--response", required=True)
    parser.add_argument("--allowed-scope", required=True)
    parser.add_argument("--patch-output", required=True)
    parser.add_argument("--paths-output", required=True)
    parser.add_argument("--max-files", type=int, required=True)
    args = parser.parse_args()
    repository = Path(args.repository).resolve()
    patch_output = Path(args.patch_output)
    patch_output.write_text(extract(Path(args.response)), encoding="utf-8")
    paths = patch_paths(repository, patch_output)
    scopes = split_scope(args.allowed_scope)
    if len(paths) > args.max_files:
        raise ValueError(f"patch changes {len(paths)} files, exceeding limit {args.max_files}")
    for path in paths:
        if not allowed(path, scopes):
            raise ValueError(f"patch path is outside Allowed-Scope: {path}")
        if Path(path).suffix.lower() in BINARY_SUFFIXES:
            raise ValueError(f"binary/object path is prohibited: {path}")
        if path.startswith(("build/", ".git/")) or "/build/" in path:
            raise ValueError(f"generated/build path is prohibited: {path}")
    check = subprocess.run(["git", "-C", str(repository), "apply", "--check", "--whitespace=error-all",
                            str(patch_output)], check=False, text=True,
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if check.returncode:
        raise ValueError("patch does not apply cleanly: " + check.stderr.strip())
    subprocess.run(["git", "-C", str(repository), "apply", "--whitespace=nowarn", str(patch_output)], check=True)
    Path(args.paths_output).write_text("\n".join(paths) + "\n", encoding="utf-8")


if __name__ == "__main__":
    try:
        main()
    except (OSError, subprocess.SubprocessError, ValueError) as error:
        print(f"patch-only validation: {error}", file=__import__("sys").stderr)
        raise SystemExit(3)
