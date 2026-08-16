#!/usr/bin/env python3

"""Context Closure promotion, outlier, prediction, and omission reports."""

import argparse
import csv
import math
from pathlib import Path
from collections import defaultdict


def read(path: Path) -> list[dict[str, str]]:
    if not path.is_file():
        return []
    with path.open(encoding="utf-8", errors="replace", newline="") as stream:
        return list(csv.DictReader(stream, delimiter="\t"))


def integer(row: dict[str, str], key: str) -> int:
    try:
        return int(row.get(key, "0"))
    except ValueError:
        return 0


def percentile(values: list[int], fraction: float) -> int:
    if not values:
        return 0
    ordered = sorted(values)
    return ordered[min(math.ceil(len(ordered) * fraction) - 1, len(ordered) - 1)]


def wilson_lower(successes: int, total: int, z: float = 1.96) -> float:
    if total == 0:
        return 0.0
    probability = successes / total
    denominator = 1 + z * z / total
    centre = probability + z * z / (2 * total)
    margin = z * math.sqrt((probability * (1 - probability) + z * z / (4 * total)) / total)
    return max(0.0, (centre - margin) / denominator)


def promotion(args: argparse.Namespace) -> None:
    outcomes = read(Path(args.project) / "logs/context-closure-outcomes.tsv")
    samples = len(outcomes)
    used = sum(integer(row, "used_paths") for row in outcomes)
    missing = sum(integer(row, "missing_candidates") for row in outcomes)
    accepted = sum(row.get("outcome") in {"ACCEPTED", "CHECKPOINTED"} for row in outcomes)
    blocked = sum(row.get("closure_status") not in {"READY", ""} for row in outcomes)
    recall = 100.0 if used + missing == 0 else used * 100.0 / (used + missing)
    success = 0.0 if samples == 0 else accepted * 100.0 / samples
    false_block = 0.0 if samples == 0 else blocked * 100.0 / samples
    checks = {
        "minimum_samples": samples >= args.min_samples,
        "file_recall": recall >= args.min_recall,
        "luna_success": success >= args.min_success,
        "false_block": false_block <= args.max_false_block,
    }
    status = "PROMOTABLE" if all(checks.values()) else "ADVISORY_ONLY"
    print("metric\tvalue")
    for key, value in (("status", status), ("samples", samples), ("file_recall_percent", f"{recall:.2f}"),
                       ("completion_percent", f"{success:.2f}"), ("false_block_percent", f"{false_block:.2f}")):
        print(f"{key}\t{value}")
    for key, value in checks.items():
        print(f"check_{key}\t{'PASS' if value else 'FAIL'}")


def predictions(args: argparse.Namespace) -> None:
    observations = read(Path(args.project) / "logs/complexity-observations.tsv")
    outcomes = read(Path(args.project) / "logs/complexity-outcomes.tsv")
    outcome_by_task = {row.get("task_id", ""): row.get("outcome", "") for row in outcomes}
    groups: dict[tuple[str, str], list[dict[str, str]]] = defaultdict(list)
    for row in observations:
        model = row.get("model", "unknown")
        leaf = row.get("leaf_type") or row.get("worker_route", "UNKNOWN")
        groups[(model, leaf)].append(row)
    print("model\tleaf_type\tsamples\tsuccesses\tcompletion_probability\tcompletion_lower_95\tprocessed_tokens_p50\tprocessed_tokens_p95\tprocessed_tokens_max\tactions_p95")
    for (model, leaf), records in sorted(groups.items()):
        success_count = sum(outcome_by_task.get(row.get("task_id", "")) in {"ACCEPTED", "CHECKPOINTED"}
                            for row in records)
        tokens = [integer(row, "processed_tokens") for row in records]
        actions = [integer(row, "items") for row in records]
        print("\t".join(map(str, (model, leaf, len(records), success_count,
                                  f"{success_count / len(records):.4f}",
                                  f"{wilson_lower(success_count, len(records)):.4f}",
                                  percentile(tokens, .5), percentile(tokens, .95), max(tokens or [0]),
                                  percentile(actions, .95)))))


def outliers(args: argparse.Namespace) -> None:
    observations = read(Path(args.project) / "logs/complexity-observations.tsv")
    scored: list[tuple[float, dict[str, str]]] = []
    for row in observations:
        actual = integer(row, "processed_tokens")
        predicted = max(integer(row, "predicted_p95_tokens"), 1)
        output = integer(row, "output_bytes")
        repeats = integer(row, "repeated_source_reads")
        score = actual / predicted + output / 32768 + repeats
        scored.append((score, row))
    print("rank\tscore\ttask_id\tplan_node\trole\tmodel\tworker_route\tprocessed_tokens\tpredicted_p95_tokens\toutput_bytes\tsource_read_bytes\trepeated_source_reads\tclassification")
    for rank, (score, row) in enumerate(sorted(scored, key=lambda value: value[0], reverse=True)[:args.limit], 1):
        print("\t".join((str(rank), f"{score:.3f}", row.get("task_id", "-"), row.get("plan_node", "-"),
                         row.get("role", "-"), row.get("model", "-"), row.get("worker_route", "-"),
                         row.get("processed_tokens", "0"), row.get("predicted_p95_tokens", "0"),
                         row.get("output_bytes", "0"), row.get("source_read_bytes", "0"),
                         row.get("repeated_source_reads", "0"), row.get("classification", "-"))))


def omissions(args: argparse.Namespace) -> None:
    counts: dict[str, int] = defaultdict(int)
    for path in sorted((Path(args.project) / "logs").glob("context-closure-usage-*.tsv")):
        for row in read(path):
            if row.get("advisory_classification") == "MISSING_CANDIDATE":
                counts[row.get("repository_path", "-")] += 1
    print("repository_path\tmissing_episodes\taction")
    for path, count in sorted(counts.items(), key=lambda item: (-item[1], item[0])):
        print(f"{path}\t{count}\t{'INDEX_OR_CLOSURE_REMEDIATION' if count >= args.minimum else 'OBSERVE'}")


def main() -> None:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="operation", required=True)
    promote = sub.add_parser("promotion")
    promote.add_argument("--project", required=True)
    promote.add_argument("--min-samples", type=int, required=True)
    promote.add_argument("--min-recall", type=float, required=True)
    promote.add_argument("--min-success", type=float, required=True)
    promote.add_argument("--max-false-block", type=float, required=True)
    predict = sub.add_parser("predictions")
    predict.add_argument("--project", required=True)
    outlier = sub.add_parser("outliers")
    outlier.add_argument("--project", required=True)
    outlier.add_argument("--limit", type=int, default=10)
    omit = sub.add_parser("omissions")
    omit.add_argument("--project", required=True)
    omit.add_argument("--minimum", type=int, default=2)
    args = parser.parse_args()
    if args.operation == "promotion":
        promotion(args)
    elif args.operation == "predictions":
        predictions(args)
    elif args.operation == "outliers":
        outliers(args)
    else:
        omissions(args)


if __name__ == "__main__":
    main()
