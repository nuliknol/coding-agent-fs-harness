#!/usr/bin/env python3

"""Compile verbose validation output into bounded, typed diagnostic evidence."""

import argparse
import csv
import hashlib
from pathlib import Path
import re


COMPILER = re.compile(
    r"^(?P<file>[^:\n]+):(?P<line>\d+)(?::(?P<column>\d+))?:\s*"
    r"(?P<severity>fatal error|error|warning|note):\s*(?P<message>.*)$",
    re.IGNORECASE)
CTEST = re.compile(
    r"^\s*\d+/\d+\s+Test\s+#?\d+:\s*(?P<test>.+?)\s+\.{2,}\*{3}(?P<state>Failed|Timeout)",
    re.IGNORECASE)
UNDEFINED = re.compile(r"(?P<prefix>.*?)(?:undefined reference to|unresolved external symbol)\s*[`'\"]?(?P<symbol>[^`'\"\s]+)", re.IGNORECASE)
SANITIZER = re.compile(r"(?:ERROR:\s*)?(?P<kind>AddressSanitizer|UndefinedBehaviorSanitizer|ThreadSanitizer):\s*(?P<message>.*)", re.IGNORECASE)
ASSERTION = re.compile(r"(?P<message>.*(?:assert(?:ion)?|expected|actual).*)", re.IGNORECASE)
GENERIC = re.compile(r"(?P<message>.*(?:fatal|error|failed|failure|timeout|segmentation fault).*)", re.IGNORECASE)
COMPILER_SOURCE_EXCERPT = re.compile(r"^\s*\d+\s*\|")
TYPED_FAILURE_KINDS = {
    "COMPILER_FATAL", "COMPILER_ERROR", "LINK_ERROR", "SANITIZER_FAILURE",
    "ASSERTION_FAILURE", "TEST_FAILURE", "TEST_TIMEOUT",
}


def normalized_message(value: str) -> str:
    value = re.sub(r"\s+", " ", value.strip())
    value = re.sub(r"\b0x[0-9a-fA-F]+\b", "<address>", value)
    return value[:2000]


def diagnostic_kind(severity: str) -> str:
    severity = severity.lower()
    if "fatal" in severity:
        return "COMPILER_FATAL"
    if severity == "error":
        return "COMPILER_ERROR"
    if severity == "warning":
        return "COMPILER_WARNING"
    return "COMPILER_NOTE"


def compile_diagnostics(log: Path, tool: str, target: str, exit_status: int) -> list[dict[str, str]]:
    records: dict[tuple[str, ...], dict[str, str]] = {}
    for raw in log.read_text(encoding="utf-8", errors="replace").splitlines():
        row = None
        match = COMPILER.match(raw)
        if match:
            row = {
                "kind": diagnostic_kind(match.group("severity")),
                "file": match.group("file"), "line": match.group("line"),
                "column": match.group("column") or "-", "symbol": "-",
                "primary_message": normalized_message(match.group("message")),
            }
        else:
            match = CTEST.match(raw)
            if match:
                row = {"kind": "TEST_TIMEOUT" if match.group("state").lower() == "timeout" else "TEST_FAILURE",
                       "file": "-", "line": "-", "column": "-",
                       "symbol": match.group("test").strip(),
                       "primary_message": normalized_message(raw)}
            else:
                match = UNDEFINED.search(raw)
                if match:
                    row = {"kind": "LINK_ERROR", "file": "-", "line": "-", "column": "-",
                           "symbol": match.group("symbol"),
                           "primary_message": normalized_message(raw)}
                else:
                    match = SANITIZER.search(raw)
                    if match:
                        row = {"kind": "SANITIZER_FAILURE", "file": "-", "line": "-", "column": "-",
                               "symbol": "-", "primary_message": normalized_message(raw)}
                    else:
                        # Compiler source excerpts commonly contain identifiers
                        # such as GPU_FAILURE or calls such as failed(...). They
                        # are quoted source, not validation diagnostics. Let the
                        # preceding location/severity line carry compiler facts.
                        match = None
                        if not COMPILER_SOURCE_EXCERPT.match(raw):
                            match = ASSERTION.search(raw) or (GENERIC.search(raw) if exit_status != 0 else None)
                        if match:
                            row = {"kind": "ASSERTION_FAILURE" if ASSERTION.search(raw) else "COMMAND_FAILURE",
                                   "file": "-", "line": "-", "column": "-", "symbol": "-",
                                   "primary_message": normalized_message(match.group("message"))}
        if not row:
            continue
        key = tuple(row[field] for field in ("kind", "file", "line", "column", "symbol", "primary_message"))
        if key in records:
            records[key]["occurrence_count"] = str(int(records[key]["occurrence_count"]) + 1)
            continue
        row.update({"tool": tool, "target": target, "causal_parent": "-", "occurrence_count": "1"})
        records[key] = row
    result = list(records.values())
    if exit_status != 0:
        # A failed build can contain thousands of unrelated warnings before its
        # actual compiler/test failure. Repair prompts are prefix-bounded, so
        # retaining warning noise here can hide the causal record and falsely
        # implicate an arbitrary source file. Prefer typed failures; generic
        # command text is only a fallback when no typed failure exists.
        typed_failures = [row for row in result if row["kind"] in TYPED_FAILURE_KINDS]
        if typed_failures:
            result = typed_failures
        else:
            generic_failures = [row for row in result if row["kind"] == "COMMAND_FAILURE"]
            result = generic_failures
    if exit_status != 0 and not result:
        result.append({"kind": "COMMAND_NONZERO_EXIT", "tool": tool, "target": target,
                       "file": "-", "line": "-", "column": "-", "symbol": "-",
                       "primary_message": f"validation command exited {exit_status} without a recognized diagnostic",
                       "causal_parent": "-", "occurrence_count": "1"})
    for index, row in enumerate(result, start=1):
        identity = "\0".join(row[field] for field in
                              ("kind", "file", "line", "column", "symbol", "primary_message"))
        row["diagnostic_id"] = "DIAG-" + hashlib.sha256(identity.encode()).hexdigest()[:16]
        if index > 1:
            row["causal_parent"] = result[0]["diagnostic_id"]
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--log", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--tool", required=True)
    parser.add_argument("--target", required=True)
    parser.add_argument("--exit-status", required=True, type=int)
    args = parser.parse_args()
    log = Path(args.log)
    output = Path(args.output)
    rows = compile_diagnostics(log, args.tool, args.target, args.exit_status)
    log_digest = hashlib.sha256(log.read_bytes()).hexdigest()
    fields = ("diagnostic_id", "kind", "tool", "target", "file", "line", "column", "symbol",
              "primary_message", "causal_parent", "occurrence_count", "full_log_sha256")
    with output.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields, delimiter="\t", lineterminator="\n")
        writer.writeheader()
        for row in rows:
            row["full_log_sha256"] = log_digest
            writer.writerow(row)
    print(len(rows))


if __name__ == "__main__":
    main()
