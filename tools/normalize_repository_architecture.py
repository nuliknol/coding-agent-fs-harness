#!/usr/bin/env python3

"""Compatibility entry point for modular architecture evidence providers."""

import argparse
from pathlib import Path

from architecture.benchmarks import benchmark_database
from architecture.inference import infer_findings
from architecture.providers import BashProvider, PythonProvider, SQLiteProvider
from architecture.reporting import write_snapshot


def normalize(args: argparse.Namespace) -> None:
    provider = SQLiteProvider(Path(args.database), args.generation)
    snapshot = provider.collect()
    if args.repository:
        snapshot.merge(BashProvider(Path(args.repository), args.generation).collect())
        snapshot.merge(PythonProvider(Path(args.repository), args.generation).collect())
    infer_findings(snapshot, args.high_fanout)
    provider.persist(snapshot)
    write_snapshot(Path(args.output), snapshot)


def main() -> None:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="operation", required=True)
    normalizer = sub.add_parser("normalize")
    normalizer.add_argument("--database", required=True)
    normalizer.add_argument("--generation", required=True)
    normalizer.add_argument("--output", required=True)
    normalizer.add_argument("--repository")
    normalizer.add_argument("--high-fanout", type=int, default=20)
    benchmark = sub.add_parser("benchmark")
    benchmark.add_argument("--database", required=True)
    benchmark.add_argument("--generation", required=True)
    benchmark.add_argument("--repository", required=True)
    benchmark.add_argument("--queries", required=True)
    benchmark.add_argument("--output", required=True)
    args = parser.parse_args()
    if args.operation == "normalize":
        normalize(args)
    else:
        benchmark_database(Path(args.database), args.generation, Path(args.repository),
                           Path(args.queries), Path(args.output))


if __name__ == "__main__":
    main()
