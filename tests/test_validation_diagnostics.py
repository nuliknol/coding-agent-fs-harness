#!/usr/bin/env python3

import csv
from pathlib import Path
import tempfile
import unittest

from tools.normalize_validation_diagnostics import compile_diagnostics


class ValidationDiagnosticsTest(unittest.TestCase):
    def test_compiler_link_test_and_duplicate_diagnostics(self):
        with tempfile.TemporaryDirectory(prefix="validation-diagnostics.") as temporary:
            log = Path(temporary) / "build.log"
            log.write_text(
                "src/a.c:12:7: error: unknown type name 'thing'\n"
                "src/a.c:12:7: error: unknown type name 'thing'\n"
                "ld: undefined reference to `missing_symbol'\n"
                "1/2 Test #1: focused_case ........***Failed\n",
                encoding="utf-8")
            rows = compile_diagnostics(log, "cc", "focused", 1)
            self.assertEqual(3, len(rows))
            self.assertEqual("COMPILER_ERROR", rows[0]["kind"])
            self.assertEqual("2", rows[0]["occurrence_count"])
            self.assertEqual("LINK_ERROR", rows[1]["kind"])
            self.assertEqual("missing_symbol", rows[1]["symbol"])
            self.assertEqual("TEST_FAILURE", rows[2]["kind"])
            self.assertEqual(rows[0]["diagnostic_id"], rows[1]["causal_parent"])

    def test_unrecognized_nonzero_exit_still_has_typed_record(self):
        with tempfile.TemporaryDirectory(prefix="validation-diagnostics.") as temporary:
            log = Path(temporary) / "command.log"
            log.write_text("opaque output\n", encoding="utf-8")
            rows = compile_diagnostics(log, "custom", "smoke", 7)
            self.assertEqual("COMMAND_NONZERO_EXIT", rows[0]["kind"])

    def test_failed_test_suppresses_warning_and_source_excerpt_noise(self):
        with tempfile.TemporaryDirectory(prefix="validation-diagnostics.") as temporary:
            log = Path(temporary) / "ctest.log"
            log.write_text(
                "src/unrelated.c:189:89: warning: enum conversion [-Wenum-conversion]\n"
                "  189 | return status == FULL ? OVERFLOW : GPU_FAILURE;\n"
                "      |                                      ^~~~~~~~~~~\n"
                "1/1 Test #1: Claims GPU normalization determinism ...***Failed 0.10 sec\n"
                "0% tests passed, 1 tests failed out of 1\n"
                "Errors while running CTest\n",
                encoding="utf-8")
            rows = compile_diagnostics(log, "bash", "focused", 8)
            self.assertEqual(1, len(rows))
            self.assertEqual("TEST_FAILURE", rows[0]["kind"])
            self.assertEqual("Claims GPU normalization determinism", rows[0]["symbol"])
            self.assertEqual("-", rows[0]["file"])
            self.assertEqual("-", rows[0]["causal_parent"])


if __name__ == "__main__":
    unittest.main()
