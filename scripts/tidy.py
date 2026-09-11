#!/usr/bin/env python3
"""One tidy row per measurement, written as a side effect of reporting.

The summarizers already parse every artifact in order to render their reports.
Rather than parse anything twice, each one can call write_rows() to dump what it
found, and this module's --merge mode concatenates those files into the
results.tsv that R/additional_report_metrics.R and any ad-hoc analysis read.

Row shape:
    ref  fims_version  stage  teardown  size  round  iteration
    source  metric  unit  value  path

A summarizer knows ref, version, source, metric, unit, value and path. It does
not know which stage or model size the benchmark asked for, so it leaves those
blank and --merge fills them in.
"""

from __future__ import annotations

import argparse
import csv
from pathlib import Path

COLUMNS = [
    "ref", "fims_version", "stage", "teardown", "size", "round", "iteration",
    "source", "metric", "unit", "value", "path",
]


def write_rows(path, rows) -> None:
    """Write tidy rows to path, filling absent columns with empty strings."""
    if path is None:
        return
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=COLUMNS, delimiter="\t",
                                extrasaction="ignore", lineterminator="\n")
        writer.writeheader()
        for row in rows:
            writer.writerow({column: row.get(column, "") for column in COLUMNS})


def merge(inputs, output, stage="", teardown="", size="") -> int:
    """Concatenate tidy files, filling in the axes only the caller knows."""
    rows = []
    for item in inputs:
        item = Path(item)
        if not item.exists():
            continue
        with item.open(encoding="utf-8", newline="") as stream:
            for row in csv.DictReader(stream, delimiter="\t"):
                for column, value in (("stage", stage), ("teardown", teardown), ("size", size)):
                    if value and not row.get(column):
                        row[column] = value
                rows.append(row)
    write_rows(output, rows)
    return len(rows)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--merge", nargs="+", required=True, metavar="TSV")
    parser.add_argument("--stage", default="")
    parser.add_argument("--teardown", default="")
    parser.add_argument("--size", default="")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    count = merge(args.merge, args.output, args.stage, args.teardown, args.size)
    print(f"Collected {count} measurements into {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
