#!/usr/bin/env python3

"""Report theoretical DAG width, current ready width, and observed occupancy."""

from __future__ import annotations

import argparse
import csv
from collections import defaultdict, deque
from datetime import datetime, timezone
from pathlib import Path


def split_csv(value: str) -> list[str]:
    return [part.strip() for part in value.split(",") if part.strip() and part.strip() != "-"]


def paths_conflict(left: list[str], right: list[str]) -> bool:
    for a in left:
        a = a.rstrip("/")
        for b in right:
            b = b.rstrip("/")
            if a == b or a.startswith(b + "/") or b.startswith(a + "/"):
                return True
    return False


def maximum_antichain_width(nodes: list[str], edges: dict[str, set[str]]) -> int:
    # Dilworth: width = |V| - maximum matching in the transitive-closure
    # bipartite graph of the partial order.
    reachable: dict[str, set[str]] = {node: set() for node in nodes}
    for start in nodes:
        pending = list(edges[start])
        while pending:
            target = pending.pop()
            if target in reachable[start]:
                continue
            reachable[start].add(target)
            pending.extend(edges[target])
    matched: dict[str, str] = {}

    def augment(left: str, seen: set[str]) -> bool:
        for right in sorted(reachable[left]):
            if right in seen:
                continue
            seen.add(right)
            if right not in matched or augment(matched[right], seen):
                matched[right] = left
                return True
        return False

    matches = sum(augment(node, set()) for node in nodes)
    return len(nodes) - matches


def parse_time(value: str) -> datetime | None:
    try:
        return datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    except ValueError:
        return None


def event_fields(message: str) -> tuple[str, dict[str, str]]:
    parts = message.split()
    values: dict[str, str] = {}
    for part in parts[1:]:
        if "=" in part:
            key, value = part.split("=", 1)
            values[key] = value
    return (parts[0] if parts else "", values)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--plan", required=True)
    parser.add_argument("--state", required=True)
    parser.add_argument("--events", required=True)
    parser.add_argument("--capacity", required=True, type=int)
    parser.add_argument("--conflicts")
    args = parser.parse_args()

    with Path(args.plan).open(encoding="utf-8", newline="") as stream:
        rows = list(csv.DictReader(stream, delimiter="\t"))
    nodes = [row["node_id"].strip() for row in rows]
    by_id = {row["node_id"].strip(): row for row in rows}
    compiled_conflicts: set[frozenset[str]] = set()
    if args.conflicts and Path(args.conflicts).exists():
        with Path(args.conflicts).open(encoding="utf-8", newline="") as stream:
            for row in csv.DictReader(stream, delimiter="\t"):
                compiled_conflicts.add(frozenset((row["left_node"], row["right_node"])))

    def nodes_conflict(left: str, right: str) -> bool:
        if args.conflicts and Path(args.conflicts).exists():
            return frozenset((left, right)) in compiled_conflicts
        return paths_conflict(split_csv(by_id[left].get("allowed_paths", "-")),
                              split_csv(by_id[right].get("allowed_paths", "-")))
    dependencies = {node: set(split_csv(by_id[node].get("depends_on", "-"))) for node in nodes}
    edges: dict[str, set[str]] = {node: set() for node in nodes}
    indegree = {node: 0 for node in nodes}
    for node, deps in dependencies.items():
        for dep in deps:
            if dep in edges:
                edges[dep].add(node)
                indegree[node] += 1

    queue = deque(sorted(node for node in nodes if indegree[node] == 0))
    longest = {node: 1 for node in nodes}
    frontier_samples: list[int] = []
    conflict_frontier_samples: list[int] = []
    visited = 0
    while queue:
        frontier_samples.append(len(queue))
        safe_frontier: list[str] = []
        for candidate in queue:
            if not any(nodes_conflict(candidate, selected) for selected in safe_frontier):
                safe_frontier.append(candidate)
        conflict_frontier_samples.append(len(safe_frontier))
        node = queue.popleft()
        visited += 1
        for target in sorted(edges[node]):
            longest[target] = max(longest[target], longest[node] + 1)
            indegree[target] -= 1
            if indegree[target] == 0:
                queue.append(target)
    cyclic = int(visited != len(nodes))

    status: dict[str, str] = {}
    with Path(args.state).open(encoding="utf-8", errors="replace") as stream:
        for line in stream:
            if not line.strip() or line.startswith("#"):
                continue
            fields = line.rstrip("\n").split("\t")
            if len(fields) >= 2:
                status[fields[0]] = fields[1]
    ready = [node for node in nodes if status.get(node) == "PENDING" and
             all(status.get(dep) == "COMPLETE" for dep in dependencies[node])]
    active = [node for node in nodes if status.get(node) == "ACTIVE"]
    selected: list[str] = []
    for candidate in ready:
        if any(nodes_conflict(candidate, item) for item in [*active, *selected]):
            continue
        selected.append(candidate)

    starts: dict[tuple[str, str, str], deque[datetime]] = defaultdict(deque)
    worker_seconds = 0.0
    first_event: datetime | None = None
    last_event: datetime | None = None
    worker_invocations = 0
    manager_invocations = 0
    if Path(args.events).exists():
        with Path(args.events).open(encoding="utf-8", errors="replace") as stream:
            for line in stream:
                timestamp, separator, message = line.rstrip("\n").partition("\t")
                if not separator:
                    continue
                when = parse_time(timestamp)
                if when is None:
                    continue
                event, values = event_fields(message)
                if event == "WORKER_INVOCATION_STARTED":
                    key = (values.get("task", "-"), values.get("session", "-"),
                           values.get("attempt", "-"))
                    starts[key].append(when)
                    worker_invocations += 1
                    first_event = when if first_event is None else min(first_event, when)
                    last_event = when if last_event is None else max(last_event, when)
                elif event == "WORKER_AGENT_PROCESS_EXITED":
                    key = (values.get("task", "-"), values.get("session", "-"),
                           values.get("attempt", "-"))
                    if starts[key]:
                        worker_seconds += max(0.0, (when - starts[key].popleft()).total_seconds())
                    last_event = when if last_event is None else max(last_event, when)
                elif event in {"MANAGER_REVIEW_STARTED", "MANAGER_PLAN_STARTED",
                               "MANAGER_REPLAN_STARTED", "MANAGER_BOOTSTRAP_STARTED",
                               "MANAGER_GOAL_CONTINUATION_REVIEW_STARTED"}:
                    manager_invocations += 1
    now = datetime.now(timezone.utc)
    for pending in starts.values():
        while pending:
            began = pending.popleft()
            worker_seconds += max(0.0, (now - began).total_seconds())
            last_event = now
    wall_seconds = 0.0 if first_event is None or last_event is None else max(
        0.0, (last_event - first_event).total_seconds())
    capacity = max(1, args.capacity)
    utilization = "N/A" if wall_seconds == 0 else f"{worker_seconds * 100 / (wall_seconds * capacity):.2f}"

    print(f"dag_cycle_detected={cyclic}")
    print(f"critical_path_length={max(longest.values(), default=0) if not cyclic else 'UNAVAILABLE'}")
    print(f"maximum_dag_width={maximum_antichain_width(nodes, edges) if not cyclic else 'UNAVAILABLE'}")
    print(f"conflict_reduced_max_width={max(conflict_frontier_samples, default=0) if not cyclic else 'UNAVAILABLE'}")
    print(f"average_ready_width={sum(frontier_samples) / len(frontier_samples):.2f}" if frontier_samples else
          "average_ready_width=0.00")
    print(f"dependency_ready_width={len(ready)}")
    print(f"safe_ready_width={len(selected)}")
    print(f"active_width={len(active)}")
    print(f"worker_invocations={worker_invocations}")
    print(f"manager_invocations={manager_invocations}")
    print(f"worker_occupied_seconds={int(worker_seconds)}")
    print(f"worker_observation_seconds={int(wall_seconds)}")
    print(f"worker_slot_utilization_percent={utilization}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
