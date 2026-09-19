"""Regression tests for persistent backup outcome reporting."""

import importlib.util
import math
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True

spec = importlib.util.spec_from_file_location("backup_metrics", Path(__file__).with_name("backup-metrics.py"))
metrics = importlib.util.module_from_spec(spec)
spec.loader.exec_module(metrics)


class BackupReportingTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)

    def values(self):
        return dict((line.split("{", 1)[0].removeprefix(metrics.PREFIX), float(line.rsplit(" ", 1)[1]))
                    for line in (self.directory / "example.prom").read_text().splitlines()
                    if not line.startswith("#"))

    def test_never_run_is_unknown(self):
        with patch.object(metrics, "completed_result", return_value=None):
            metrics.report(self.directory, "example", seed=True)
        self.assertEqual(self.values()["job_info"], 1)
        self.assertTrue(math.isnan(self.values()["last_run_success"]))
        self.assertTrue(math.isnan(self.values()["last_success_timestamp_seconds"]))

    def test_failure_preserves_success_across_process_restart(self):
        metrics.report(self.directory, "example", (100, True))
        subprocess.run(["python3", str(Path(metrics.__file__)), "--directory", str(self.directory), "example"],
                       env={"PATH": os.environ["PATH"], "SERVICE_RESULT": "exit-code", "EXIT_CODE": "exited", "EXIT_STATUS": "1"}, check=True)
        self.assertEqual(self.values()["last_run_success"], 0)
        self.assertEqual(self.values()["last_success_timestamp_seconds"], 100)
        self.assertGreater(self.values()["last_completion_timestamp_seconds"], 100)
        with patch.object(metrics, "completed_result", side_effect=AssertionError("must not reseed persisted state")):
            metrics.report(self.directory, "example", seed=True)

    def test_clean_signal_is_interrupted_not_successful(self):
        metrics.report(self.directory, "example", (100, True))
        subprocess.run(["python3", str(Path(metrics.__file__)), "--directory", str(self.directory), "example"],
                       env={"PATH": os.environ["PATH"], "SERVICE_RESULT": "success", "EXIT_CODE": "killed", "EXIT_STATUS": "TERM"}, check=True)
        self.assertEqual(self.values()["last_run_success"], 0)
        self.assertEqual(self.values()["last_success_timestamp_seconds"], 100)

    def test_seed_completed_success_and_failure(self):
        for success in (True, False):
            (self.directory / "example.prom").unlink(missing_ok=True)
            with patch.object(metrics, "completed_result", return_value=(123, success)):
                metrics.report(self.directory, "example", seed=True)
            self.assertEqual(self.values()["last_run_success"], int(success))
            self.assertEqual(self.values()["last_completion_timestamp_seconds"], 123)
            if success:
                self.assertEqual(self.values()["last_success_timestamp_seconds"], 123)
            else:
                self.assertTrue(math.isnan(self.values()["last_success_timestamp_seconds"]))

    def test_unavailable_systemd_still_exports_inventory(self):
        with patch.object(metrics, "completed_result", side_effect=subprocess.CalledProcessError(1, "systemctl")):
            metrics.report(self.directory, "example", seed=True)
        self.assertEqual(self.values()["job_info"], 1)

    def test_atomic_failure_leaves_previous_metrics(self):
        metrics.report(self.directory, "example", (100, True))
        before = (self.directory / "example.prom").read_bytes()
        with patch.object(metrics.os, "replace", side_effect=OSError("write failure")):
            with self.assertRaises(OSError):
                metrics.report(self.directory, "example", (200, False))
        self.assertEqual((self.directory / "example.prom").read_bytes(), before)
        self.assertFalse(list(self.directory.glob("*.tmp")))


if __name__ == "__main__":
    unittest.main()
