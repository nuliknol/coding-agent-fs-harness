#!/usr/bin/env python3

"""Compare advisory Context Closure paths with one worker transcript."""

import argparse
import csv
import json
from pathlib import Path
import re
import shlex


PATH_TOKEN = re.compile(r"[A-Za-z0-9_.+@-]+(?:/[A-Za-z0-9_.+@-]+)+")


def closure_records(path: Path) -> dict[str, str]:
    records: dict[str, str] = {}
    with path.open(encoding="utf-8", errors="replace", newline="") as stream:
        for row in csv.DictReader(stream, delimiter="\t"):
            source = row.get("source_path", "")
            required = row.get("required", "SUPPORTING")
            if source and (source not in records or required == "REQUIRED"):
                records[source] = required
    return records


def normalized_candidate(repository: Path, token: str) -> str | None:
    token = token.strip("'\"`()[]{}<>,;|")
    token = re.sub(r":\d+(?::\d+)?$", "", token)
    if not token or any(character in token for character in "*$?"):
        return None
    candidate = Path(token)
    if candidate.is_absolute():
        try:
            relative = candidate.resolve().relative_to(repository)
        except (OSError, ValueError):
            return None
    else:
        relative = Path(token)
        candidate = repository / relative
    try:
        resolved = candidate.resolve()
        relative = resolved.relative_to(repository)
    except (OSError, ValueError):
        return None
    return relative.as_posix() if resolved.is_file() else None


def command_paths(repository: Path, command: str, closure_paths: set[str]) -> set[str]:
    result = {path for path in closure_paths if path in command}
    candidates = PATH_TOKEN.findall(command)
    try:
        candidates.extend(shlex.split(command))
    except ValueError:
        pass
    for token in candidates:
        path = normalized_candidate(repository, token)
        if path:
            result.add(path)
    return result


def nested_paths(repository: Path, value: object, result: set[str]) -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            if key in ("path", "file_path", "filename") and isinstance(child, str):
                path = normalized_candidate(repository, child)
                if path:
                    result.add(path)
            nested_paths(repository, child, result)
    elif isinstance(value, list):
        for child in value:
            nested_paths(repository, child, result)


def analyze(args: argparse.Namespace) -> None:
    repository = Path(args.repository).resolve()
    closure = closure_records(Path(args.closure))
    observed: set[str] = set()
    changed: set[str] = set()
    commands = 0
    with Path(args.jsonl).open(encoding="utf-8", errors="replace") as stream:
        for line in stream:
            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                continue
            item = event.get("item", {}) if isinstance(event, dict) else {}
            if not isinstance(item, dict):
                continue
            if item.get("type") == "command_execution":
                commands += 1
                observed.update(command_paths(repository, str(item.get("command", "")), set(closure)))
            item_type = str(item.get("type", "")).lower()
            discovered: set[str] = set()
            nested_paths(repository, item, discovered)
            observed.update(discovered)
            if "change" in item_type or "patch" in item_type or "write" in item_type:
                changed.update(discovered)
    all_paths = sorted(set(closure).union(observed).union(changed))
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream, delimiter="\t", lineterminator="\n")
        writer.writerow(("repository_path", "closure_membership", "required", "observed_in_transcript",
                         "changed_by_item", "advisory_classification"))
        for path in all_paths:
            membership = "IN_CLOSURE" if path in closure else "OUTSIDE_CLOSURE"
            required = closure.get(path, "-")
            was_observed = path in observed
            was_changed = path in changed
            if path not in closure:
                classification = "MISSING_CANDIDATE"
            elif was_changed or was_observed:
                classification = "USED"
            else:
                classification = "UNUSED_CANDIDATE"
            writer.writerow((path, membership, required, int(was_observed), int(was_changed), classification))
    used = len(set(closure).intersection(observed.union(changed)))
    unused = len(set(closure).difference(observed.union(changed)))
    missing = len(observed.union(changed).difference(closure))
    changed_outside = len(changed.difference(closure))
    Path(args.summary).write_text(
        f"commands={commands}\nclosure_paths={len(closure)}\nused_paths={used}\n"
        f"unused_candidates={unused}\nmissing_candidates={missing}\n"
        f"changed_outside_closure={changed_outside}\n",
        encoding="utf-8",
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repository", required=True)
    parser.add_argument("--closure", required=True)
    parser.add_argument("--jsonl", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--summary", required=True)
    analyze(parser.parse_args())


if __name__ == "__main__":
    main()
