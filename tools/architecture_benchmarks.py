#!/usr/bin/env python3

import argparse
from pathlib import Path

from architecture.benchmarks import benchmark_database, benchmark_maps


def main() -> None:
    parser = argparse.ArgumentParser()
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--database")
    source.add_argument("--maps-dir")
    parser.add_argument("--generation", required=True)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--queries", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    common = (Path(args.repository), Path(args.queries), Path(args.output))
    if args.database:
        benchmark_database(Path(args.database), args.generation, *common)
    else:
        benchmark_maps(Path(args.maps_dir), *common)


if __name__ == "__main__":
    main()
