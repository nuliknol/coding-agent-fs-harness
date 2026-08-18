#!/usr/bin/env python3

"""Build source-only architecture evidence without a compilation database."""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess

from architecture.inference import infer_findings
from architecture.model import ArchitectureSnapshot
from architecture.providers import BashProvider, PythonProvider
from architecture.reporting import write_snapshot


def git_revision(repository: Path) -> str:
    result = subprocess.run(["git", "-C", str(repository), "rev-parse", "HEAD"],
                            check=True, text=True, stdout=subprocess.PIPE)
    return result.stdout.strip()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repository", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--generation")
    parser.add_argument("--high-fanout", type=int, default=20)
    args = parser.parse_args()
    repository = Path(args.repository).resolve()
    revision = git_revision(repository)
    provider_sources = [Path(__file__), Path(__file__).parent / "architecture/providers/bash_provider.py",
                        Path(__file__).parent / "architecture/providers/python_provider.py"]
    provider_hash = hashlib.sha256(b"".join(path.read_bytes() for path in provider_sources)).hexdigest()
    generation = args.generation or "source-" + hashlib.sha256(
        f"{repository}\0{revision}\0{provider_hash}".encode()).hexdigest()
    snapshot = ArchitectureSnapshot(generation)
    snapshot.merge(BashProvider(repository, generation).collect())
    snapshot.merge(PythonProvider(repository, generation).collect())
    infer_findings(snapshot, args.high_fanout)
    output = Path(args.output)
    write_snapshot(output, snapshot)
    manifest = {
        "schema_version": 1, "status": "READY", "generation": generation,
        "repository": str(repository), "source_revision": revision,
        "provider_fingerprint": provider_hash,
        "providers": ["bash-static", "python-ast"],
    }
    (output / "manifest.json").write_text(json.dumps(manifest, sort_keys=True, indent=2) + "\n", encoding="utf-8")
    print(f"SOURCE_ARCHITECTURE_READY generation={generation} path={output}")


if __name__ == "__main__":
    main()
