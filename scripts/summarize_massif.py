#!/usr/bin/env python3
"""Create a Markdown summary from one or more Valgrind Massif runs."""

from __future__ import annotations

import argparse
import datetime as dt
import glob
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Optional


@dataclass
class Profile:
    path: Path
    command: str = "unknown"
    time_unit: str = "unknown"
    snapshots: int = 0
    peak_snapshot: int = 0
    peak_time: int = 0
    peak_heap: int = 0
    peak_extra: int = 0
    peak_stacks: int = 0

    @property
    def peak_total(self) -> int:
        return self.peak_heap + self.peak_extra + self.peak_stacks


@dataclass
class Run:
    ref: str
    version: str
    prefix: Path
    profiles: list[Profile]

    @property
    def primary(self) -> Optional[Profile]:
        return max(self.profiles, key=lambda item: item.peak_total, default=None)


def parse_massif(path: Path) -> Profile:
    profile = Profile(path=path)
    current: dict[str, int] = {}

    def finish_snapshot() -> None:
        if "snapshot" not in current:
            return
        profile.snapshots += 1
        total = sum(current.get(key, 0) for key in ("mem_heap_B", "mem_heap_extra_B", "mem_stacks_B"))
        if total >= profile.peak_total:
            profile.peak_snapshot = current["snapshot"]
            profile.peak_time = current.get("time", 0)
            profile.peak_heap = current.get("mem_heap_B", 0)
            profile.peak_extra = current.get("mem_heap_extra_B", 0)
            profile.peak_stacks = current.get("mem_stacks_B", 0)

    with path.open(encoding="utf-8", errors="replace") as stream:
        for raw_line in stream:
            line = raw_line.rstrip("\n")
            if line.startswith("cmd:"):
                profile.command = line[4:].strip()
            elif line.startswith("time_unit:"):
                profile.time_unit = line.split(":", 1)[1].strip()
            elif line.startswith("snapshot="):
                finish_snapshot()
                current = {"snapshot": int(line.split("=", 1)[1])}
            elif "=" in line:
                key, value = line.split("=", 1)
                if key in {"time", "mem_heap_B", "mem_heap_extra_B", "mem_stacks_B"}:
                    try:
                        current[key] = int(value)
                    except ValueError:
                        pass
    finish_snapshot()
    return profile


def human_bytes(value: int) -> str:
    units = ("B", "KiB", "MiB", "GiB", "TiB")
    amount = float(value)
    for unit in units:
        if abs(amount) < 1024 or unit == units[-1]:
            return f"{amount:,.0f} {unit}" if unit == "B" else f"{amount:,.2f} {unit}"
        amount /= 1024
    raise AssertionError("unreachable")


def signed_bytes(baseline: int, comparison: int) -> str:
    delta = comparison - baseline
    prefix = "+" if delta > 0 else "−" if delta < 0 else ""
    return f"{prefix}{human_bytes(abs(delta))}"


def percent_delta(baseline: int, comparison: int) -> str:
    if baseline == 0:
        return "0.00%" if comparison == 0 else "n/a"
    return f"{(comparison - baseline) / baseline * 100:+.2f}%"


def describe_bytes(label: str, baseline: int, comparison: int) -> str:
    delta = comparison - baseline
    if delta == 0:
        return f"{label} was unchanged at {human_bytes(comparison)}."
    direction = "increased" if delta > 0 else "decreased"
    return (
        f"{label} {direction} by {human_bytes(abs(delta))} "
        f"({percent_delta(baseline, comparison)}), from {human_bytes(baseline)} to {human_bytes(comparison)}."
    )


def md_escape(value: str) -> str:
    return value.replace("|", "\\|").replace("\n", " ")


def relative(path: Path, report_path: Path) -> str:
    return os.path.relpath(path, report_path.parent)


def render(runs: list[Run], report_path: Path) -> str:
    timestamp = dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat()
    lines = [
        "# FIMS Valgrind Massif Benchmark Report",
        "",
        f"Generated: `{timestamp}`",
        "",
        "## Summary",
        "",
        "Massif measures allocated heap memory over the lifetime of each process. "
        "The peak below is heap plus allocator overhead and stacks. It is not a leak count.",
        "",
        "| Git ref | FIMS version | Peak total | Heap | Heap overhead | Stacks | Snapshots |",
        "|---|---:|---:|---:|---:|---:|---:|",
    ]
    for run in runs:
        peak = run.primary
        if peak is None:
            lines.append(f"| {md_escape(run.ref)} | {md_escape(run.version)} | no data | — | — | — | — |")
        else:
            lines.append(
                f"| {md_escape(run.ref)} | {md_escape(run.version)} | **{human_bytes(peak.peak_total)}** "
                f"| {human_bytes(peak.peak_heap)} | {human_bytes(peak.peak_extra)} "
                f"| {human_bytes(peak.peak_stacks)} | {peak.snapshots:,} |"
            )

    valid = [run for run in runs if run.primary is not None]
    if len(valid) == 2:
        baseline, comparison = valid
        baseline_peak = baseline.primary.peak_total  # type: ignore[union-attr]
        delta = comparison.primary.peak_total - baseline_peak  # type: ignore[union-attr]
        percent = (delta / baseline_peak * 100) if baseline_peak else 0.0
        if delta == 0:
            comparison_text = (
                f"`{comparison.ref}` and `{baseline.ref}` had **the same peak memory** "
                f"({human_bytes(baseline_peak)}; {percent:+.2f}%)."
            )
        else:
            direction = "more" if delta > 0 else "less"
            comparison_text = (
                f"`{comparison.ref}` used **{human_bytes(abs(delta))} {direction} peak memory** than "
                f"`{baseline.ref}` ({percent:+.2f}%)."
            )
        first = baseline.primary
        second = comparison.primary
        lines.extend([
            "", "## Detailed branch comparison", "", comparison_text, "",
            "Positive deltas mean the comparison ref used more memory; negative deltas mean less.",
            "",
            f"| Metric | `{baseline.ref}` | `{comparison.ref}` | Delta | Change |",
            "|---|---:|---:|---:|---:|",
            f"| Peak total | {human_bytes(first.peak_total)} | {human_bytes(second.peak_total)} | {signed_bytes(first.peak_total, second.peak_total)} | {percent_delta(first.peak_total, second.peak_total)} |",
            f"| Heap bytes | {human_bytes(first.peak_heap)} | {human_bytes(second.peak_heap)} | {signed_bytes(first.peak_heap, second.peak_heap)} | {percent_delta(first.peak_heap, second.peak_heap)} |",
            f"| Heap overhead | {human_bytes(first.peak_extra)} | {human_bytes(second.peak_extra)} | {signed_bytes(first.peak_extra, second.peak_extra)} | {percent_delta(first.peak_extra, second.peak_extra)} |",
            f"| Stack bytes | {human_bytes(first.peak_stacks)} | {human_bytes(second.peak_stacks)} | {signed_bytes(first.peak_stacks, second.peak_stacks)} | {percent_delta(first.peak_stacks, second.peak_stacks)} |",
            f"| Snapshots | {first.snapshots:,} | {second.snapshots:,} | {second.snapshots - first.snapshots:+,} | {percent_delta(first.snapshots, second.snapshots)} |",
            "",
            f"The peak occurred at Massif time `{first.peak_time:,}` for `{baseline.ref}` and `{second.peak_time:,}` for `{comparison.ref}`. "
            "Massif time is instruction count by default, so this indicates execution position rather than wall-clock duration.",
            "", "### Interpretation", "",
            f"- {describe_bytes('Peak total memory', first.peak_total, second.peak_total)}",
            f"- {describe_bytes('Peak heap memory', first.peak_heap, second.peak_heap)}",
            f"- {describe_bytes('Allocator overhead at peak', first.peak_extra, second.peak_extra)}",
            f"- {describe_bytes('Stack memory at peak', first.peak_stacks, second.peak_stacks)}",
        ])

    lines.extend(["", "## Run details", ""])
    for run in runs:
        lines.extend([f"### `{run.ref}` (FIMS {run.version})", ""])
        if not run.profiles:
            lines.extend([f"No readable Massif files matched `{run.prefix.name}.*`.", ""])
            continue
        lines.extend([
            "Because child tracing is enabled, a run may contain multiple process profiles. "
            "The process with the largest peak is used in the summary.",
            "",
            "| Output file | Peak total | Peak snapshot | Peak time | Time unit | Command |",
            "|---|---:|---:|---:|---|---|",
        ])
        for profile in sorted(run.profiles, key=lambda item: item.peak_total, reverse=True):
            output = relative(profile.path, report_path)
            lines.append(
                f"| [{md_escape(profile.path.name)}]({md_escape(output)}) | {human_bytes(profile.peak_total)} "
                f"| {profile.peak_snapshot} | {profile.peak_time:,} | {md_escape(profile.time_unit)} "
                f"| `{md_escape(profile.command)}` |"
            )
        lines.append("")

    lines.extend([
        "## Interpretation notes",
        "",
        "- Compare peaks only when both branches ran the same model, stage, inputs, and Valgrind options.",
        "- `Heap overhead` is Massif's estimate of allocator bookkeeping and alignment costs.",
        "- `Stacks` is zero unless Massif stack profiling is enabled with `--stacks=yes`.",
        "- Use `ms_print <massif-output-file>` for the allocation tree and snapshot graph.",
        "",
    ])
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", nargs=3, action="append", metavar=("REF", "VERSION", "PREFIX"), required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    runs = []
    for ref, version, prefix_text in args.run:
        prefix = Path(prefix_text)
        paths = [Path(item) for item in glob.glob(f"{glob.escape(str(prefix))}.*")]
        profiles = []
        for path in sorted(paths):
            try:
                profiles.append(parse_massif(path))
            except (OSError, ValueError) as error:
                print(f"warning: could not parse {path}: {error}")
        runs.append(Run(ref=ref, version=version, prefix=prefix, profiles=profiles))

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(render(runs, args.output), encoding="utf-8")
    print(f"Markdown report written to {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
