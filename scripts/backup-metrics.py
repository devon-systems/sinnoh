"""Persist restic completion outcomes for node_exporter without affecting backups."""

import argparse
import fcntl
import json
import os
from pathlib import Path
import subprocess
import tempfile
import sys
import time

PREFIX = "sinnoh_backup_"


def completed_result(job):
    """Only seed from an exited main process in a completed systemd service."""
    output = subprocess.check_output(
        ["systemctl", "show", f"restic-backups-{job}.service",
         "--property=ActiveState,Result,ExecMainExitTimestamp,ExecMainExitTimestampMonotonic,ExecMainCode,ExecMainStatus"],
        text=True,
    )
    properties = dict(line.split("=", 1) for line in output.splitlines())
    if (properties.get("ActiveState") not in ("inactive", "failed")
            or int(properties.get("ExecMainExitTimestampMonotonic", "0")) == 0):
        return None
    timestamp = float(subprocess.check_output(
        ["date", "--date", properties["ExecMainExitTimestamp"], "+%s"], text=True))
    return timestamp, (properties["Result"] == "success"
                       and properties.get("ExecMainCode") == "1"
                       and properties.get("ExecMainStatus") == "0")


def report(directory, job, completion=None, seed=False):
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    # Inventory and outcome share one atomically replaced file. The lock also
    # serializes a first completion with boot-time seeding.
    destination = directory / f"{job}.prom"
    with (directory / f"{job}.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        values = {
            "job_info": 1,
            "last_completion_timestamp_seconds": "NaN",
            "last_success_timestamp_seconds": "NaN",
            "last_run_success": "NaN",
        }
        if destination.exists():
            for line in destination.read_text().splitlines():
                if line.startswith(PREFIX):
                    metric, value = line.rsplit(" ", 1)
                    values[metric.split("{", 1)[0].removeprefix(PREFIX)] = value
            if seed:
                return
        if seed:
            try:
                completion = completed_result(job)
            except (subprocess.SubprocessError, ValueError, KeyError) as error:
                print(f"Cannot seed {job}: {error}", file=sys.stderr)
        if completion is not None:
            timestamp, success = completion
            values["last_completion_timestamp_seconds"] = timestamp
            values["last_run_success"] = int(success)
            if success:
                values["last_success_timestamp_seconds"] = timestamp
        descriptor, temporary = tempfile.mkstemp(dir=directory, suffix=".tmp")
        try:
            with os.fdopen(descriptor, "w") as output:
                os.fchmod(output.fileno(), 0o644)
                for metric, value in values.items():
                    output.write(f'# TYPE {PREFIX}{metric} gauge\n')
                    output.write(f'{PREFIX}{metric}{{backup={json.dumps(job)}}} {value}\n')
                output.flush()
                os.fsync(output.fileno())
            os.replace(temporary, destination)
            directory_fd = os.open(directory, os.O_DIRECTORY)
            try:
                os.fsync(directory_fd)
            finally:
                os.close(directory_fd)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", default="/var/lib/sinnoh-backup-metrics")
    parser.add_argument("--seed", action="store_true")
    parser.add_argument("job")
    arguments = parser.parse_args()
    try:
        completion = None if arguments.seed else (time.time(), (os.environ.get("SERVICE_RESULT") == "success"
            and os.environ.get("EXIT_CODE") == "exited"
            and os.environ.get("EXIT_STATUS") == "0"))
        report(arguments.directory, arguments.job, completion, arguments.seed)
    except Exception as error:
        # Reporting is best-effort. ExecStopPost must preserve the backup result.
        print(f"Backup metrics for {arguments.job}: {error}", file=sys.stderr)
