#!/usr/bin/env python3
"""Create a Markdown comparison from macOS /usr/bin/time -l profiles."""

from __future__ import annotations

import argparse
import datetime as dt
import platform
import re
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path
from typing import Optional


@dataclass
class Profile:
    path: Path
    elapsed_seconds: Optional[float] = None
    user_seconds: Optional[float] = None
    system_seconds: Optional[float] = None
    maximum_rss: Optional[int] = None
    peak_footprint: Optional[int] = None
    page_reclaims: Optional[int] = None
    page_faults: Optional[int] = None
    swaps: Optional[int] = None


@dataclass
class Run:
    ref: str
    version: str
    profile: Profile
    trace_status: str
    trace_path: Path
    allocations: dict[str, dict[str, int]]


def parse_profile(path: Path) -> Profile:
    profile = Profile(path=path)
    text = path.read_text(encoding="utf-8", errors="replace")
    timing = re.search(
        r"([0-9.]+)\s+real\s+([0-9.]+)\s+user\s+([0-9.]+)\s+sys", text
    )
    if timing:
        profile.elapsed_seconds = float(timing.group(1))
        profile.user_seconds = float(timing.group(2))
        profile.system_seconds = float(timing.group(3))

    fields = {
        "maximum resident set size": "maximum_rss",
        "peak memory footprint": "peak_footprint",
        "page reclaims": "page_reclaims",
        "page faults": "page_faults",
        "swaps": "swaps",
    }
    for label, attribute in fields.items():
        match = re.search(rf"^\s*([0-9]+)\s+{re.escape(label)}\s*$", text, re.MULTILINE)
        if match:
            setattr(profile, attribute, int(match.group(1)))
    return profile


def parse_allocation_stats(trace_path: Path) -> dict[str, dict[str, int]]:
    stats_path = trace_path.with_name(trace_path.stem + "_statistics.xml")
    if not stats_path.exists():
        return {}
    result = {}
    try:
        root = ET.parse(stats_path).getroot()
    except (ET.ParseError, OSError):
        return result
    for row in root.iter("row"):
        category = row.get("category")
        if not category:
            continue
        result[category] = {
            key: int(row.get(key, "0"))
            for key in (
                "persistent-bytes", "transient-bytes", "total-bytes",
                "count-persistent", "count-transient", "count-total", "count-events",
            )
        }
    return result


def human_bytes(value: Optional[int]) -> str:
    if value is None:
        return "—"
    amount = float(value)
    for unit in ("B", "KiB", "MiB", "GiB", "TiB"):
        if amount < 1024 or unit == "TiB":
            return f"{amount:,.0f} {unit}" if unit == "B" else f"{amount:,.2f} {unit}"
        amount /= 1024
    raise AssertionError("unreachable")


def number(value: Optional[int]) -> str:
    return "—" if value is None else f"{value:,}"


def seconds(value: Optional[float]) -> str:
    return "—" if value is None else f"{value:,.2f} s"


def percent_delta(baseline: Optional[float], comparison: Optional[float]) -> str:
    if baseline is None or comparison is None:
        return "—"
    if baseline == 0:
        return "0.00%" if comparison == 0 else "n/a"
    return f"{(comparison - baseline) / baseline * 100:+.2f}%"


def signed_bytes(baseline: Optional[int], comparison: Optional[int]) -> str:
    if baseline is None or comparison is None:
        return "—"
    delta = comparison - baseline
    prefix = "+" if delta > 0 else "−" if delta < 0 else ""
    return f"{prefix}{human_bytes(abs(delta))}"


def signed_number(baseline: Optional[float], comparison: Optional[float], suffix: str = "") -> str:
    if baseline is None or comparison is None:
        return "—"
    delta = comparison - baseline
    return f"{delta:+,.2f}{suffix}" if isinstance(delta, float) else f"{delta:+,}{suffix}"


def describe_change(label: str, baseline: Optional[float], comparison: Optional[float], formatter) -> str:
    if baseline is None or comparison is None:
        return f"{label} could not be compared because one run did not report it."
    delta = comparison - baseline
    if delta == 0:
        return f"{label} was unchanged at {formatter(comparison)}."
    direction = "increased" if delta > 0 else "decreased"
    return (
        f"{label} {direction} by {formatter(abs(delta))} "
        f"({percent_delta(baseline, comparison)}), from {formatter(baseline)} to {formatter(comparison)}."
    )


def escape(value: str) -> str:
    return value.replace("|", "\\|").replace("\n", " ")


def render(runs: list[Run], output: Path) -> str:
    generated = dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat()
    mac_version = platform.mac_ver()[0] or "unknown"
    lines = [
        "# FIMS macOS Native Memory Benchmark Report",
        "",
        f"Generated: `{generated}`  ",
        f"Host: `macOS {mac_version} ({platform.machine()})`  ",
        "Profilers: Instruments Allocations and `/usr/bin/time -l`",
        "",
        "## Summary",
        "",
        "macOS reports process-level physical memory rather than Massif's allocated heap. "
        "Maximum resident set size (RSS) is the primary comparison metric; peak memory "
        "footprint is also shown when the host provides it.",
        "",
        "| Git ref | FIMS version | Maximum RSS | Peak footprint | Elapsed | Instruments |",
        "|---|---:|---:|---:|---:|---|",
    ]
    for run in runs:
        item = run.profile
        instruments = "captured" if run.trace_status == "captured" else run.trace_status
        lines.append(
            f"| {escape(run.ref)} | {escape(run.version)} | **{human_bytes(item.maximum_rss)}** "
            f"| {human_bytes(item.peak_footprint)} | {seconds(item.elapsed_seconds)} | {instruments} |"
        )

    comparable = [run for run in runs if run.profile.maximum_rss is not None]
    if len(comparable) == 2:
        baseline, comparison = comparable
        base = baseline.profile.maximum_rss or 0
        other = comparison.profile.maximum_rss or 0
        delta = other - base
        percent = delta / base * 100 if base else 0.0
        if delta == 0:
            sentence = f"`{comparison.ref}` and `{baseline.ref}` had the same maximum RSS ({human_bytes(base)})."
        else:
            direction = "more" if delta > 0 else "less"
            sentence = (
                f"`{comparison.ref}` used **{human_bytes(abs(delta))} {direction} maximum RSS** "
                f"than `{baseline.ref}` ({percent:+.2f}%)."
            )
        lines.extend([
            "", "## Detailed branch comparison", "", sentence, "",
            "Positive deltas mean the comparison ref used more of that metric; negative deltas mean less.",
            "",
            f"| Metric | `{baseline.ref}` | `{comparison.ref}` | Delta | Change |",
            "|---|---:|---:|---:|---:|",
            f"| Maximum RSS | {human_bytes(baseline.profile.maximum_rss)} | {human_bytes(comparison.profile.maximum_rss)} | {signed_bytes(baseline.profile.maximum_rss, comparison.profile.maximum_rss)} | {percent_delta(baseline.profile.maximum_rss, comparison.profile.maximum_rss)} |",
            f"| Peak footprint | {human_bytes(baseline.profile.peak_footprint)} | {human_bytes(comparison.profile.peak_footprint)} | {signed_bytes(baseline.profile.peak_footprint, comparison.profile.peak_footprint)} | {percent_delta(baseline.profile.peak_footprint, comparison.profile.peak_footprint)} |",
            f"| Elapsed time | {seconds(baseline.profile.elapsed_seconds)} | {seconds(comparison.profile.elapsed_seconds)} | {signed_number(baseline.profile.elapsed_seconds, comparison.profile.elapsed_seconds, ' s')} | {percent_delta(baseline.profile.elapsed_seconds, comparison.profile.elapsed_seconds)} |",
            f"| User CPU time | {seconds(baseline.profile.user_seconds)} | {seconds(comparison.profile.user_seconds)} | {signed_number(baseline.profile.user_seconds, comparison.profile.user_seconds, ' s')} | {percent_delta(baseline.profile.user_seconds, comparison.profile.user_seconds)} |",
            f"| System CPU time | {seconds(baseline.profile.system_seconds)} | {seconds(comparison.profile.system_seconds)} | {signed_number(baseline.profile.system_seconds, comparison.profile.system_seconds, ' s')} | {percent_delta(baseline.profile.system_seconds, comparison.profile.system_seconds)} |",
            f"| Page reclaims | {number(baseline.profile.page_reclaims)} | {number(comparison.profile.page_reclaims)} | {signed_number(baseline.profile.page_reclaims, comparison.profile.page_reclaims)} | {percent_delta(baseline.profile.page_reclaims, comparison.profile.page_reclaims)} |",
            f"| Page faults | {number(baseline.profile.page_faults)} | {number(comparison.profile.page_faults)} | {signed_number(baseline.profile.page_faults, comparison.profile.page_faults)} | {percent_delta(baseline.profile.page_faults, comparison.profile.page_faults)} |",
            f"| Swaps | {number(baseline.profile.swaps)} | {number(comparison.profile.swaps)} | {signed_number(baseline.profile.swaps, comparison.profile.swaps)} | {percent_delta(baseline.profile.swaps, comparison.profile.swaps)} |",
            "", "### Interpretation", "",
            f"- {describe_change('Maximum RSS', baseline.profile.maximum_rss, comparison.profile.maximum_rss, human_bytes)}",
            f"- {describe_change('Peak memory footprint', baseline.profile.peak_footprint, comparison.profile.peak_footprint, human_bytes)}",
            f"- {describe_change('Elapsed time', baseline.profile.elapsed_seconds, comparison.profile.elapsed_seconds, lambda value: f'{value:,.2f} s')}",
            f"- {describe_change('Page faults', baseline.profile.page_faults, comparison.profile.page_faults, lambda value: f'{value:,.0f}')}",
        ])

        aggregate_name = "All Heap & Anonymous VM"
        first_aggregate = baseline.allocations.get(aggregate_name)
        second_aggregate = comparison.allocations.get(aggregate_name)
        if first_aggregate and second_aggregate:
            lines.extend([
                "", "### Instruments allocation totals", "",
                "Persistent bytes were still allocated at the end of the recording; transient bytes were allocated and freed during the recorded interval.",
                "",
                f"| Metric | `{baseline.ref}` | `{comparison.ref}` | Delta | Change |",
                "|---|---:|---:|---:|---:|",
            ])
            allocation_metrics = (
                ("Persistent bytes", "persistent-bytes", True),
                ("Transient bytes", "transient-bytes", True),
                ("Total recorded bytes", "total-bytes", True),
                ("Persistent allocations", "count-persistent", False),
                ("Transient allocations", "count-transient", False),
                ("Total allocations", "count-total", False),
                ("Allocation events", "count-events", False),
            )
            for label, key, is_bytes in allocation_metrics:
                first_value = first_aggregate[key]
                second_value = second_aggregate[key]
                formatter = human_bytes if is_bytes else number
                delta_formatter = signed_bytes if is_bytes else signed_number
                lines.append(
                    f"| {label} | {formatter(first_value)} | {formatter(second_value)} | "
                    f"{delta_formatter(first_value, second_value)} | {percent_delta(first_value, second_value)} |"
                )
            lines.extend([
                "",
                f"- {describe_change('Persistent allocated memory', first_aggregate['persistent-bytes'], second_aggregate['persistent-bytes'], human_bytes)}",
                f"- {describe_change('Transient allocated memory', first_aggregate['transient-bytes'], second_aggregate['transient-bytes'], human_bytes)}",
                f"- {describe_change('Allocation events', first_aggregate['count-events'], second_aggregate['count-events'], lambda value: f'{value:,.0f}')}",
            ])

            aggregate_categories = {
                "destroyed event", "All Heap & Anonymous VM", "All Heap Allocations",
                "All Anonymous VM", "All VM Regions",
            }
            categories = (set(baseline.allocations) | set(comparison.allocations)) - aggregate_categories
            changed_categories = [
                category for category in categories
                if comparison.allocations.get(category, {}).get("persistent-bytes", 0)
                != baseline.allocations.get(category, {}).get("persistent-bytes", 0)
            ]
            ranked = sorted(
                changed_categories,
                key=lambda category: abs(
                    comparison.allocations.get(category, {}).get("persistent-bytes", 0)
                    - baseline.allocations.get(category, {}).get("persistent-bytes", 0)
                ),
                reverse=True,
            )[:10]
            if ranked:
                lines.extend([
                    "", "### Largest persistent-allocation category changes", "",
                    f"| Category | `{baseline.ref}` | `{comparison.ref}` | Delta | Change |",
                    "|---|---:|---:|---:|---:|",
                ])
                for category in ranked:
                    first_value = baseline.allocations.get(category, {}).get("persistent-bytes", 0)
                    second_value = comparison.allocations.get(category, {}).get("persistent-bytes", 0)
                    lines.append(
                        f"| {escape(category)} | {human_bytes(first_value)} | {human_bytes(second_value)} | "
                        f"{signed_bytes(first_value, second_value)} | {percent_delta(first_value, second_value)} |"
                    )

    lines.extend(["", "## Run details", ""])
    for run in runs:
        item = run.profile
        toc_path = run.trace_path.with_name(run.trace_path.stem + "_toc.xml")
        stats_path = run.trace_path.with_name(run.trace_path.stem + "_statistics.xml")
        log_path = run.trace_path.with_suffix(".log")
        lines.extend([
            f"### `{run.ref}` (FIMS {run.version})",
            "",
            "| Metric | Value |",
            "|---|---:|",
            f"| Maximum resident set size | {human_bytes(item.maximum_rss)} |",
            f"| Peak memory footprint | {human_bytes(item.peak_footprint)} |",
            f"| Elapsed time | {seconds(item.elapsed_seconds)} |",
            f"| User CPU time | {seconds(item.user_seconds)} |",
            f"| System CPU time | {seconds(item.system_seconds)} |",
            f"| Page reclaims | {number(item.page_reclaims)} |",
            f"| Page faults | {number(item.page_faults)} |",
            f"| Swaps | {number(item.swaps)} |",
            "",
            f"Raw profile: [{escape(item.path.name)}]({escape(item.path.name)})",
            "",
        ])
        if run.trace_status.startswith("captured"):
            lines.append(
                f"Instruments trace: [{escape(run.trace_path.name)}]({escape(run.trace_path.name)})  "
            )
            if toc_path.exists():
                lines.append(f"Trace table of contents: [{escape(toc_path.name)}]({escape(toc_path.name)})  ")
            if stats_path.exists():
                lines.append(f"Allocation statistics: [{escape(stats_path.name)}]({escape(stats_path.name)})")
            if log_path.exists():
                lines.append(f"Instruments log: [{escape(log_path.name)}]({escape(log_path.name)})")
            lines.extend([
                "",
                "Open the `.trace` bundle in Instruments to inspect allocation lifetimes, "
                "persistent versus transient allocations, types, and recorded stack traces.",
                "",
            ])
        else:
            lines.extend([
                f"Instruments Allocations status: **{escape(run.trace_status)}**.",
                "",
                *(
                    [f"Instruments log: [{escape(log_path.name)}]({escape(log_path.name)})", ""]
                    if log_path.exists()
                    else []
                ),
                "If capture failed, allow your terminal or Codex under **System Settings → "
                "Privacy & Security → Developer Tools**, then rerun the benchmark.",
                "",
            ])

    lines.extend([
        "## Interpretation notes",
        "",
        "- Compare runs only when both refs use the same model, inputs, and benchmark stage.",
        "- Maximum RSS includes resident code and mapped pages, so it is broader than Massif heap usage.",
        "- Peak footprint is Apple's accounting of the process's physical-memory impact and may be lower than RSS.",
        "- Instruments and the RSS profiler execute the model separately to avoid profiling the Instruments launcher itself.",
        "- The `.trace` bundle is the authoritative detailed allocation record; exported XML is provided for automation.",
        "- macOS and Massif results should be compared within their own profiler type, not directly across operating systems.",
        "",
    ])
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--run",
        nargs=5,
        action="append",
        metavar=("REF", "VERSION", "PROFILE", "TRACE_STATUS", "TRACE_PATH"),
        required=True,
    )
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    runs = [
        Run(
            ref,
            version,
            parse_profile(Path(profile_path)),
            status,
            Path(trace_path),
            parse_allocation_stats(Path(trace_path)),
        )
        for ref, version, profile_path, status, trace_path in args.run
    ]
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(render(runs, args.output), encoding="utf-8")
    print(f"Markdown report written to {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
