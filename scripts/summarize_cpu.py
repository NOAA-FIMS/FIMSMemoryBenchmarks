#!/usr/bin/env python3
"""Summarize macOS Instruments or Linux perf CPU profiles."""

from __future__ import annotations

import argparse
import datetime as dt
import re
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path


@dataclass
class Run:
    ref: str
    version: str
    status: str
    path: Path
    symbols: list[tuple[str, float]]


def mac_symbols(path: Path) -> list[tuple[str, float]]:
    if not path.exists():
        return []
    totals: dict[str, float] = {}
    try:
        root = ET.parse(path).getroot()
    except (ET.ParseError, OSError):
        return []
    references = {node.get("id"): node for node in root.iter() if node.get("id")}

    def dereference(node):
        return references.get(node.get("ref"), node) if node is not None else None

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
            totals[symbol] = totals.get(symbol, 0) + weight
    return sorted(totals.items(), key=lambda item: item[1], reverse=True)[:15]


def perf_symbols(path: Path) -> list[tuple[str, float]]:
    if not path.exists():
        return []
    result = []
    pattern = re.compile(r"^\s*([0-9.]+)%\s+\S+\s+\S+\s+(?:\[[^.]+\.\]\s+)?(.+?)\s*$")
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        match = pattern.match(line)
        if match:
            result.append((match.group(2), float(match.group(1))))
    return result[:15]


def render(runs: list[Run], platform_name: str) -> str:
    profiler = "Instruments Time Profiler" if platform_name == "Darwin" else "Linux perf"
    lines = [
        "# FIMS CPU Profile Report", "",
        f"Generated: `{dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat()}`  ",
        f"Profiler: {profiler}", "", "## Summary", "",
        "Each branch is sampled in a separate model run after its FIMS build is installed.", "",
        "| Git ref | FIMS version | Capture status | Profile data |",
        "|---|---:|---|---|",
    ]
    for run in runs:
        link = f"[{run.path.name}]({run.path.name})" if run.path.exists() else "—"
        lines.append(f"| {run.ref} | {run.version} | {run.status} | {link} |")
    lines.extend(["", "## Hot symbols by branch", ""])
    for run in runs:
        lines.extend([f"### `{run.ref}`", ""])
        if not run.symbols:
            lines.extend(["No exported symbol samples were available. Open the native profile artifact for interactive analysis.", ""])
            continue
        label = "Samples" if platform_name == "Darwin" else "Overhead"
        lines.extend([f"| Rank | Symbol | {label} |", "|---:|---|---:|"])
        total = sum(value for _, value in run.symbols) or 1
        for rank, (symbol, value) in enumerate(run.symbols, 1):
            shown = f"{value / total * 100:.2f}%" if platform_name == "Darwin" else f"{value:.2f}%"
            lines.append(f"| {rank} | `{symbol.replace('|', chr(92) + '|')}` | {shown} |")
        lines.append("")
    lines.extend([
        "## Interpretation notes", "",
        "- Sampling identifies where CPU time is spent without tracing every function call.",
        "- Compare hot-symbol rankings across refs; small percentage changes can be sampling noise.",
        "- Open `.trace` files in Instruments or `perf.data` with perf for full call trees.", "",
    ])
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", required=True)
    parser.add_argument("--run", nargs=4, action="append", required=True, metavar=("REF", "VERSION", "STATUS", "PATH"))
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    parse = mac_symbols if args.platform == "Darwin" else perf_symbols
    runs = [Run(ref, version, status, Path(path), parse(Path(path))) for ref, version, status, path in args.run]
    args.output.write_text(render(runs, args.platform), encoding="utf-8")
    print(f"CPU Markdown report written to {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
