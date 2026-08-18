#!/usr/bin/env python3

"""Compatibility CLI for versioned architecture scorecards."""

import argparse
from pathlib import Path

from architecture.scorecard import from_database, from_maps, write_scorecard


def main() -> None:
    parser = argparse.ArgumentParser()
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--database")
    source.add_argument("--maps-dir")
    parser.add_argument("--generation", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--proposal", required=True)
    parser.add_argument("--benchmarks")
    args = parser.parse_args()
    benchmarks = Path(args.benchmarks) if args.benchmarks else None
    if args.database:
        metrics, findings = from_database(Path(args.database), args.generation, benchmarks)
    else:
        metrics, findings = from_maps(Path(args.maps_dir), args.generation, benchmarks)
    write_scorecard(Path(args.output), Path(args.proposal), metrics, findings)


if __name__ == "__main__":
    main()
