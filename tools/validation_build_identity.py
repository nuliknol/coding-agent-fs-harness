#!/usr/bin/env python3

"""Fingerprint stable CMake build identities named by one validation command."""

import argparse
import hashlib
from pathlib import Path
import shlex


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--command", required=True)
    parser.add_argument("--cwd", required=True)
    parser.add_argument("--private-root")
    args = parser.parse_args()
    try:
        tokens = shlex.split(args.command)
    except ValueError:
        tokens = args.command.split()
    builds: set[Path] = set()
    index = 0
    while index < len(tokens):
        token = tokens[index]
        value = None
        if token in {"-B", "--build"} and index + 1 < len(tokens):
            value = tokens[index + 1]
            index += 1
        elif token.startswith("-B") and len(token) > 2:
            value = token[2:]
        if value:
            requested = (Path(args.cwd) / value).resolve() if not Path(value).is_absolute() else Path(value).resolve()
            if args.private_root:
                key = hashlib.sha256(str(requested).encode()).hexdigest()
                builds.add(Path(args.private_root) / key)
            else:
                builds.add(requested)
        index += 1
    digest = hashlib.sha256()
    if not builds:
        digest.update(b"no-cmake-build\0")
    for build in sorted(builds, key=str):
        digest.update(str(build).encode() + b"\0")
        for name in ("CMakeCache.txt", ".harness-cmake-identity.env"):
            path = build / name
            digest.update(name.encode() + b"\0")
            if path.is_file():
                digest.update(hashlib.sha256(path.read_bytes()).digest())
            else:
                digest.update(b"missing")
    print("sha256:" + digest.hexdigest())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
