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


def section_has_content(lines: list[str], heading: str) -> bool:
    try:
        start = lines.index(heading) + 1
    except ValueError:
        return False
    for line in lines[start:]:
        if line.startswith("## "):
            break
        if line.strip():
            return True
    return False


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
    # Strip every inherited execution field first.  Older assignments are not
    # uniform: some have Root-Criterion, some only Target-Criterion, and some
    # place identity below a continuation preamble.  Trying to splice relative
    # to one of those optional fields can silently omit the target or duplicate
    # task identity.  Emit one canonical header independently of source layout.
    controlled.update({"Task-ID", "Task-Root", "Target-Criterion", "Context-Closure-Cut"})
    body: list[str] = []
    for line in lines:
        key = line.split(": ", 1)[0] if ": " in line else ""
        if key in controlled:
            continue
        body.append(line)

    header_order = (
        "Task-ID", "Task-Root", "Worker-Context", "Target-Criterion",
        "Context-Closure-Cut", "Replan-Strategy-ID", "Strategy-Change",
        "Supersedes-Task", "Manager-Remediation", "Blocker-Class",
        "Remediation-Scope", "Goal-ID", "Goal-Success-Evidence", "Allowed-Scope",
        "Context-Paths", "Required-Symbols", "Focused-Validation",
    )
    rendered = [f"{key}: {replacements[key]}" for key in header_order
                if key in replacements]
    rendered.extend(["", *body])
    required_sections = (
        ("## Objective",
         f"Execute deterministic Context Closure cut {child_id} for "
         f"{args.target_criterion}."),
        ("## Acceptance criteria", row["acceptance_evidence"]),
        ("## Validation commands", row["focused_validation"]),
    )
    for heading, content in required_sections:
        if not section_has_content(rendered, heading):
            rendered.extend(["", heading, "", content])
    Path(args.output).write_text("\n".join(rendered).rstrip() + "\n", encoding="utf-8")
    print(f"child_id={child_id}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
