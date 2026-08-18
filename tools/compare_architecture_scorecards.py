#!/usr/bin/env python3

"""Direction-aware, benchmark-safe architecture scorecard comparison."""

from __future__ import annotations

import argparse
import csv
from pathlib import Path


def read(path: Path) -> dict[str, tuple[str, str, str]]:
    with path.open(encoding="utf-8", newline="") as stream:
        rows = list(csv.DictReader(stream, delimiter="\t"))
    if not rows or "metric" not in rows[0] or "value" not in rows[0]:
        raise ValueError(f"invalid scorecard: {path}")
    return {row["metric"]: (row["value"], row.get("direction", "INFORMATIONAL"),
                            row.get("regression_threshold", "-")) for row in rows}


def number(value: str) -> float | None:
    try:
        return float(value)
    except ValueError:
        return None


def exceeds_threshold(old: float, new: float, direction: str, threshold: str) -> bool:
    if threshold == "-" or direction == "INFORMATIONAL":
        return False
    percent = threshold.endswith("%")
    try:
        allowed = float(threshold[:-1] if percent else threshold)
    except ValueError:
        return False
    deterioration = new - old if direction == "LOWER" else old - new
    if deterioration <= 0:
        return False
    if percent:
        return old == 0 or deterioration * 100.0 / abs(old) > allowed
    return deterioration > allowed


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("before")
    parser.add_argument("after")
    parser.add_argument("--max-recall-regression", type=float, default=1.0)
    parser.add_argument("--max-context-regression-percent", type=float, default=10.0)
    args = parser.parse_args()
    before = read(Path(args.before))
    after = read(Path(args.after))
    benchmark_before = before.get("benchmark_set_sha256", ("-", "INFORMATIONAL", "-"))[0]
    benchmark_after = after.get("benchmark_set_sha256", ("-", "INFORMATIONAL", "-"))[0]
    comparable = benchmark_before == benchmark_after and benchmark_before != "-"
    rows: list[tuple[str, str, str, str, str, str]] = []
    regressed = False
    for metric in sorted(set(before) | set(after)):
        old, old_direction, old_threshold = before.get(metric, ("-", "INFORMATIONAL", "-"))
        new, new_direction, new_threshold = after.get(metric, ("-", old_direction, old_threshold))
        direction = new_direction if new_direction != "INFORMATIONAL" else old_direction
        threshold = new_threshold if new_threshold != "-" else old_threshold
        old_number, new_number = number(old), number(new)
        delta = "-"
        verdict = "INFORMATIONAL"
        if old_number is not None and new_number is not None:
            difference = new_number - old_number
            delta = f"{difference:g}"
            if direction == "LOWER":
                verdict = "IMPROVED" if difference < 0 else "REGRESSED" if difference > 0 else "UNCHANGED"
            elif direction == "HIGHER":
                verdict = "IMPROVED" if difference > 0 else "REGRESSED" if difference < 0 else "UNCHANGED"
        if old_number is not None and new_number is not None and exceeds_threshold(
                old_number, new_number, direction, threshold):
            regressed = True
        if comparable and metric == "navigation_recall_percent" and old_number is not None and new_number is not None:
            if old_number - new_number > args.max_recall_regression:
                regressed = True
        if comparable and metric == "context_bytes_per_query" and old_number and new_number is not None:
            if (new_number - old_number) * 100.0 / old_number > args.max_context_regression_percent:
                regressed = True
        rows.append((metric, old, new, delta, direction, threshold, verdict))
    writer = csv.writer(__import__("sys").stdout, delimiter="\t", lineterminator="\n")
    writer.writerow(("metric", "before", "after", "delta", "direction", "regression_threshold", "verdict"))
    writer.writerows(rows)
    if benchmark_before != benchmark_after:
        print("comparison_status\tINCOMPARABLE\tbenchmark-set-mismatch")
        return 3
    status = "REGRESSION" if regressed else "PASS"
    print(f"comparison_status\t{status}\t-")
    return 4 if regressed else 0


if __name__ == "__main__":
    raise SystemExit(main())
