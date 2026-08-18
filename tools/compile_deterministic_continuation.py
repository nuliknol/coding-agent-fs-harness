#!/usr/bin/env python3

"""Compile one manager-free continuation from a trusted Context Closure cut."""

import argparse
import csv
from pathlib import Path


def metadata(lines: list[str]) -> dict[str, str]:
    values: dict[str, str] = {}
    for line in lines:
        if ": " in line:
            key, value = line.split(": ", 1)
            values.setdefault(key, value)
    return values


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--assignment", required=True)
    parser.add_argument("--repair-children", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--task-id", required=True)
    parser.add_argument("--task-root", required=True)
    parser.add_argument("--target-criterion", required=True)
    parser.add_argument("--supersedes", required=True)
    parser.add_argument("--manager-remediation", action="store_true")
    parser.add_argument("--closure-cut", action="store_true")
    args = parser.parse_args()

    assignment_path = Path(args.assignment)
    lines = assignment_path.read_text(encoding="utf-8", errors="replace").splitlines()
    values = metadata(lines)
    with Path(args.repair_children).open(encoding="utf-8", newline="") as stream:
        rows = list(csv.DictReader(stream, delimiter="\t"))
    if not rows:
        raise SystemExit("repair-children.tsv contains no compiled cuts")
    row = sorted(rows, key=lambda item: (int(item.get("sequence", "0")),
                                         item.get("child_id", "")))[0]
    child_id = row["child_id"]
    replacements = {
        "Task-ID": args.task_id,
        "Task-Root": args.task_root,
        "Worker-Context": "FRESH",
        "Target-Criterion": args.target_criterion,
        "Goal-ID": f"deterministic-closure-{args.task_id}-{child_id}",
        "Goal-Success-Evidence": row["acceptance_evidence"],
        "Allowed-Scope": row["allowed_paths"],
        "Context-Paths": row["context_paths"],
        "Required-Symbols": row["required_symbols"],
        "Focused-Validation": row["focused_validation"],
        "Replan-Strategy-ID": f"deterministic.closure.{args.task_id}.{child_id}",
        "Strategy-Change": ("REPAIR_PREREQUISITE" if args.manager_remediation
                            else "NEW_EVIDENCE"),
        "Supersedes-Task": args.supersedes,
    }
    if args.manager_remediation:
        replacements.update({
            "Manager-Remediation": "1",
            "Blocker-Class": values.get("Blocker-Class", "LOCAL_CODE_PREREQUISITE"),
            "Remediation-Scope": row["allowed_paths"],
        })
    if args.closure_cut:
        replacements["Context-Closure-Cut"] = child_id

    controlled = set(replacements)
    if not args.manager_remediation:
        controlled.update({"Manager-Remediation", "Blocker-Class", "Remediation-Scope"})
    output: list[str] = []
    inserted = False
    for line in lines:
        key = line.split(": ", 1)[0] if ": " in line else ""
        if key in controlled:
            continue
        output.append(line)
        if key == "Task-Root" and not inserted:
            for replacement_key in (
                    "Worker-Context", "Replan-Strategy-ID", "Strategy-Change",
                    "Supersedes-Task", "Manager-Remediation", "Blocker-Class",
                    "Remediation-Scope"):
                if replacement_key in replacements:
                    output.append(f"{replacement_key}: {replacements[replacement_key]}")
            inserted = True

    # Identity is part of the controlled field set and is therefore deliberately
    # removed above.  Rebuild the complete execution header in one canonical
    # place so an old assignment cannot retain stale retry/remediation metadata.
    if not inserted:
        header = [f"Task-ID: {args.task_id}", f"Task-Root: {args.task_root}"]
        for replacement_key in (
                "Worker-Context", "Replan-Strategy-ID", "Strategy-Change",
                "Supersedes-Task", "Manager-Remediation", "Blocker-Class",
                "Remediation-Scope"):
            if replacement_key in replacements:
                header.append(f"{replacement_key}: {replacements[replacement_key]}")
        output = [*header, *output]
    identity_keys = {"Task-ID", "Task-Root"}
    rendered: list[str] = []
    for line in output:
        key = line.split(": ", 1)[0] if ": " in line else ""
        if key in identity_keys:
            if key == "Task-ID":
                rendered.append(f"Task-ID: {args.task_id}")
            elif key == "Task-Root":
                rendered.append(f"Task-Root: {args.task_root}")
            continue
        if key == "Root-Criterion":
            rendered.append(line)
            rendered.append(f"Target-Criterion: {replacements['Target-Criterion']}")
            if args.closure_cut:
                rendered.append(f"Context-Closure-Cut: {child_id}")
            continue
        if key in {"Goal-ID", "Goal-Success-Evidence", "Allowed-Scope", "Context-Paths",
                   "Required-Symbols", "Focused-Validation", "Target-Criterion",
                   "Context-Closure-Cut"}:
            continue
        rendered.append(line)

    # Replace or add execution metadata immediately before the first section.
    insertion = next((index for index, line in enumerate(rendered)
                      if line.startswith("## ")), len(rendered))
    existing_keys = {line.split(": ", 1)[0] for line in rendered[:insertion] if ": " in line}
    leaf_fields = ("Goal-ID", "Goal-Success-Evidence", "Allowed-Scope", "Context-Paths",
                   "Required-Symbols", "Focused-Validation")
    additions = [f"{key}: {replacements[key]}" for key in leaf_fields
                 if key not in existing_keys]
    rendered[insertion:insertion] = additions
    Path(args.output).write_text("\n".join(rendered).rstrip() + "\n", encoding="utf-8")
    print(f"child_id={child_id}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
