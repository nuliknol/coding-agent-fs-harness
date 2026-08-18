#!/usr/bin/env python3

import argparse
from pathlib import Path

from architecture.rebuild_report import generate


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-dir", required=True)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--status")
    args = parser.parse_args()
    report, debt = generate(Path(args.run_dir), Path(args.repository), args.status)
    print(f"ARCHITECTURE_REBUILD_REPORT_READY report={report} debt={debt}")


if __name__ == "__main__":
    main()
