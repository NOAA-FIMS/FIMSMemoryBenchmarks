#!/usr/bin/env python3
"""Record successful command wall time in seconds using a monotonic clock."""

import argparse
from pathlib import Path
import subprocess
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command
    if command[:1] == ["--"]:
        command = command[1:]
    if not command:
        parser.error("a command is required")
    # Never leave a successful timing from an earlier invocation after failure.
    args.output.unlink(missing_ok=True)
    started = time.perf_counter()
    result = subprocess.run(command)
    elapsed = time.perf_counter() - started
    if result.returncode == 0:
        args.output.write_text(f"{elapsed:.9f}\n", encoding="utf-8")
    return result.returncode if result.returncode >= 0 else 128 - result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
