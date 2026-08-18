#!/usr/bin/env python3

"""Verify a live workspace diff against optional indexed mutation regions."""

import argparse
from pathlib import Path
import subprocess

from apply_worker_patch import validate_mutation_regions


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repository", required=True)
    parser.add_argument("--capabilities", required=True)
    parser.add_argument("--plan-node", required=True)
    parser.add_argument("paths", nargs="+")
    args = parser.parse_args()
    result = subprocess.run(
        ["git", "-C", args.repository, "diff", "--no-ext-diff", "--unified=0", "HEAD", "--",
         *args.paths], check=False, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode:
        print(result.stderr, end="", file=__import__("sys").stderr)
        return result.returncode
    validate_mutation_regions(result.stdout, Path(args.capabilities), args.plan_node)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError) as error:
        print(f"mutation-region validation: {error}", file=__import__("sys").stderr)
        raise SystemExit(3)
