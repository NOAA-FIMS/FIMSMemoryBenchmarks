#!/usr/bin/env python3
"""Turn every profiler artifact of one run into tidy rows.

Massif files, `/usr/bin/time -l` profiles, Instruments allocation statistics and
CPU traces, and `perf report` text all describe the same run in different
shapes. This reads them and writes one table:

    ref  fims_version  stage  teardown  size  round  iteration
    source  metric  unit  value  path

so scripts/report.py -- and anything you write in R -- has a single input.
Anything already in this shape -- timing rows from bench::mark(), say -- can be
merged in with --tidy.

Inputs are listed in a TSV the shell scripts append to as they run, with
columns: kind, ref, version, stage, round, tag, path. `kind` is one of
massif, time, instruments-alloc, instruments-cpu, perf, cpu-status.
"""

from __future__ import annotations

import argparse
import csv
import glob
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

COLUMNS = [
    "ref", "fims_version", "stage", "teardown", "size", "round", "iteration",
    "source", "metric", "unit", "value", "path",
]

TOP_SYMBOLS = 15
TOP_CATEGORIES = 10


# --------------------------------------------------------------------------
# Parsers, one per artifact type
# --------------------------------------------------------------------------

def parse_massif(path: Path) -> dict[str, object]:
    """Peak, final snapshot, and provenance from one Massif output file."""
    peak = {"heap": 0, "extra": 0, "stacks": 0}
    final = {"heap": 0, "extra": 0, "stacks": 0}
    peak_snapshot = 0
    peak_time = 0
    snapshots = 0
    command = "unknown"
    time_unit = "unknown"
    current: dict[str, int] = {}

    def finish() -> None:
        nonlocal snapshots, peak, final, peak_snapshot, peak_time
        if "snapshot" not in current:
            return
        snapshots += 1
        totals = {
            "heap": current.get("mem_heap_B", 0),
            "extra": current.get("mem_heap_extra_B", 0),
            "stacks": current.get("mem_stacks_B", 0),
        }
        if sum(totals.values()) >= sum(peak.values()):
            peak = dict(totals)
            peak_snapshot = current["snapshot"]
            peak_time = current.get("time", 0)
        # Snapshots are written in order, so the last one is the exit state.
        final = dict(totals)

    with path.open(encoding="utf-8", errors="replace") as stream:
        for raw in stream:
            line = raw.rstrip("\n")
            if line.startswith("cmd:"):
                command = line[4:].strip()
            elif line.startswith("time_unit:"):
                time_unit = line.split(":", 1)[1].strip()
            elif line.startswith("snapshot="):
                finish()
                current = {"snapshot": int(line.split("=", 1)[1])}
            elif "=" in line:
                key, value = line.split("=", 1)
                if key in {"time", "mem_heap_B", "mem_heap_extra_B", "mem_stacks_B"}:
                    try:
                        current[key] = int(value)
                    except ValueError:
                        pass
    finish()

    return {
        "peak_total": sum(peak.values()),
        "peak_heap": peak["heap"],
        "peak_extra": peak["extra"],
        "peak_stacks": peak["stacks"],
        "retained_total": sum(final.values()),
        "retained_heap": final["heap"],
        "snapshots": snapshots,
        "peak_snapshot": peak_snapshot,
        "peak_time": peak_time,
        "command": command,
        "time_unit": time_unit,
    }


TIME_FIELDS = {
    "maximum resident set size": ("maximum_rss", "bytes"),
    "peak memory footprint": ("peak_footprint", "bytes"),
    "page reclaims": ("page_reclaims", "count"),
    "page faults": ("page_faults", "count"),
    "swaps": ("swaps", "count"),
}


def parse_time_l(path: Path) -> list[tuple[str, str, float]]:
    """(metric, unit, value) from a `/usr/bin/time -l` profile."""
    text = path.read_text(encoding="utf-8", errors="replace")
    rows: list[tuple[str, str, float]] = []

    timing = re.search(r"([0-9.]+)\s+real\s+([0-9.]+)\s+user\s+([0-9.]+)\s+sys", text)
    if timing:
        rows.append(("elapsed_seconds", "seconds", float(timing.group(1))))
        rows.append(("user_seconds", "seconds", float(timing.group(2))))
        rows.append(("system_seconds", "seconds", float(timing.group(3))))

    for label, (metric, unit) in TIME_FIELDS.items():
        match = re.search(rf"^\s*([0-9]+)\s+{re.escape(label)}\s*$", text, re.MULTILINE)
        if match:
            rows.append((metric, unit, float(match.group(1))))
    return rows


def parse_allocation_stats(trace_path: Path) -> list[tuple[str, str, float]]:
    """Totals and the largest categories from an Instruments statistics export."""
    stats_path = trace_path.with_name(trace_path.stem + "_statistics.xml")
    if not stats_path.exists():
        return []
    try:
        root = ET.parse(stats_path).getroot()
    except (ET.ParseError, OSError):
        return []

    categories: dict[str, dict[str, int]] = {}
    for row in root.iter("row"):
        category = row.get("category")
        if not category:
            continue
        categories[category] = {
            key: int(row.get(key, "0"))
            for key in ("persistent-bytes", "transient-bytes", "total-bytes",
                        "count-persistent", "count-transient")
        }

    rows: list[tuple[str, str, float]] = []
    for key, metric in (("persistent-bytes", "persistent_bytes"),
                        ("transient-bytes", "transient_bytes"),
                        ("total-bytes", "allocated_bytes")):
        rows.append((metric, "bytes", float(sum(item[key] for item in categories.values()))))

    largest = sorted(categories.items(), key=lambda item: item[1]["persistent-bytes"], reverse=True)
    for category, values in largest[:TOP_CATEGORIES]:
        rows.append((f"persistent_bytes:{category}", "bytes", float(values["persistent-bytes"])))
    return rows


def parse_perf_symbols(path: Path) -> list[tuple[str, str, float]]:
    """Top symbols and their overhead percentages from `perf report --stdio`."""
    pattern = re.compile(r"^\s*([0-9.]+)%\s+\S+\s+\S+\s+(?:\[[^.]+\.\]\s+)?(.+?)\s*$")
    found: list[tuple[str, str, float]] = []
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        match = pattern.match(line)
        if match:
            found.append((f"symbol:{match.group(2)}", "percent", float(match.group(1))))
        if len(found) >= TOP_SYMBOLS:
            break
    return found


def parse_instruments_cpu(path: Path) -> list[tuple[str, str, float]]:
    """Top symbols and their sample weights from an Instruments time-profile export."""
    try:
        root = ET.parse(path).getroot()
    except (ET.ParseError, OSError):
        return []
    references = {node.get("id"): node for node in root.iter() if node.get("id")}

    def dereference(node):
        return references.get(node.get("ref"), node) if node is not None else None

    totals: dict[str, float] = {}
    for row in root.iter("row"):
        weight_node = dereference(row.find("weight"))
        try:
            weight = float(weight_node.text) if weight_node is not None and weight_node.text else 1.0
        except ValueError:
            weight = 1.0
        symbol = row.get("symbol") or row.get("name")
        if not symbol:
            backtrace = dereference(row.find("backtrace"))
            frame = dereference(backtrace.find("frame")) if backtrace is not None else None
            if frame is not None:
                symbol = frame.get("name") or (frame.text or "").strip()
        if symbol:
            totals[symbol] = totals.get(symbol, 0.0) + weight

    ranked = sorted(totals.items(), key=lambda item: item[1], reverse=True)[:TOP_SYMBOLS]
    return [(f"symbol:{symbol}", "samples", weight) for symbol, weight in ranked]


# --------------------------------------------------------------------------
# Driving the parsers from the inputs table
# --------------------------------------------------------------------------

def read_inputs(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8", newline="") as stream:
        return [row for row in csv.DictReader(stream, delimiter="\t") if row.get("kind")]


def collect(inputs: list[dict[str, str]], teardown: str, size: str) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []

    def add(entry, source, metric, unit, value, path):
        rows.append({
            "ref": entry.get("ref", ""),
            "fims_version": entry.get("version", ""),
            "stage": entry.get("stage", ""),
            "teardown": teardown,
            "size": size,
            "round": entry.get("round", ""),
            "iteration": entry.get("round", ""),
            "source": source,
            "metric": metric,
            "unit": unit,
            "value": value,
            "path": path,
        })

    for entry in inputs:
        kind = entry["kind"]
        target = Path(entry.get("path", ""))

        if kind == "massif":
            # memory.sh writes "<out>_<pid>", one file per process: the R process
            # and every child Valgrind traced. The largest peak is the one being
            # measured; the rest are reported as per-process detail.
            matches = sorted(Path(item) for item in glob.glob(f"{glob.escape(str(target))}_*"))
            parsed = []
            for match in matches:
                try:
                    parsed.append((match, parse_massif(match)))
                except (OSError, ValueError) as error:
                    print(f"warning: could not parse {match}: {error}", file=sys.stderr)
            if not parsed:
                print(f"warning: no Massif files matched {target}_*", file=sys.stderr)
                continue
            path, metrics = max(parsed, key=lambda item: item[1]["peak_total"])
            byte_metrics = {"peak_total", "peak_heap", "peak_extra", "peak_stacks",
                            "retained_total", "retained_heap"}
            for metric, value in metrics.items():
                if metric in {"command", "time_unit"}:
                    continue
                unit = "bytes" if metric in byte_metrics else "count"
                add(entry, "massif", metric, unit, value, path.name)
            add(entry, "massif", "processes", "count", len(parsed), path.name)

            # With --trace-children a round covers the R process and everything
            # it spawned. One row per process keeps that visible, so a surprising
            # peak can be traced to the process that caused it.
            for process_path, process_metrics in sorted(
                parsed, key=lambda item: item[1]["peak_total"], reverse=True
            ):
                for metric in ("peak_total", "retained_total", "snapshots",
                               "peak_snapshot", "peak_time"):
                    unit = "bytes" if metric in byte_metrics else "count"
                    add(entry, "massif", f"process_{metric}", unit,
                        process_metrics[metric], process_path.name)
                add(entry, "massif", "process_command", "text",
                    process_metrics["command"], process_path.name)

        elif kind == "time":
            if not target.exists():
                continue
            for metric, unit, value in parse_time_l(target):
                add(entry, "time", metric, unit, value, target.name)

        elif kind == "instruments-alloc":
            for metric, unit, value in parse_allocation_stats(target):
                add(entry, "instruments", metric, unit, value, target.name)

        elif kind == "perf":
            if not target.exists():
                continue
            for metric, unit, value in parse_perf_symbols(target):
                add(entry, "cpu", metric, unit, value, target.name)

        elif kind == "instruments-cpu":
            if not target.exists():
                continue
            for metric, unit, value in parse_instruments_cpu(target):
                add(entry, "cpu", metric, unit, value, target.name)

        elif kind == "cpu-status":
            # Text, not a measurement: it is what the report shows when no
            # profile was captured, instead of an empty table.
            add(entry, "cpu", "status", "text", entry.get("tag", "unknown"), target.name)

        else:
            print(f"warning: unknown input kind '{kind}'", file=sys.stderr)

    return rows


def read_tidy(path: Path) -> list[dict[str, object]]:
    if not path.exists():
        return []
    with path.open(encoding="utf-8", newline="") as stream:
        rows = []
        for row in csv.DictReader(stream, delimiter="\t"):
            rows.append({column: row.get(column, "") for column in COLUMNS})
        return rows


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--inputs", type=Path, help="TSV of artifacts to parse")
    parser.add_argument("--tidy", type=Path, nargs="*", default=[],
                        help="TSVs already in tidy form, merged as-is")
    parser.add_argument("--teardown", default="")
    parser.add_argument("--size", default="default")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    rows: list[dict[str, object]] = []
    if args.inputs and args.inputs.exists():
        rows.extend(collect(read_inputs(args.inputs), args.teardown, args.size))
    for tidy in args.tidy:
        rows.extend(read_tidy(tidy))

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=COLUMNS, delimiter="\t",
                                extrasaction="ignore", lineterminator="\n")
        writer.writeheader()
        for row in rows:
            writer.writerow({column: row.get(column, "") for column in COLUMNS})

    print(f"Collected {len(rows)} measurements into {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
