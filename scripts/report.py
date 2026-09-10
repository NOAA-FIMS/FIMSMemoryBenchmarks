#!/usr/bin/env python3
"""Render one Markdown report from the tidy table scripts/collect.py writes.

Sections appear only when the run produced the data for them, so a missing
profiler shows as one explicit line rather than an empty table.
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import statistics
from collections import OrderedDict
from pathlib import Path

LADDER = ("initialize", "assemble", "tape", "evaluate", "optimize", "sdreport")


# --------------------------------------------------------------------------
# Reading and formatting
# --------------------------------------------------------------------------

def read_rows(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8", newline="") as stream:
        return list(csv.DictReader(stream, delimiter="\t"))


def numeric(rows, **filters) -> list[float]:
    values = []
    for row in rows:
        if all(row.get(key, "") == value for key, value in filters.items()):
            try:
                values.append(float(row["value"]))
            except (KeyError, TypeError, ValueError):
                continue
    return values


def median_of(rows, **filters):
    values = numeric(rows, **filters)
    return statistics.median(values) if values else None


def human_bytes(value) -> str:
    if value is None:
        return "—"
    amount = float(value)
    for unit in ("B", "KiB", "MiB", "GiB", "TiB"):
        if abs(amount) < 1024 or unit == "TiB":
            return f"{amount:,.0f} {unit}" if unit == "B" else f"{amount:,.2f} {unit}"
        amount /= 1024
    raise AssertionError("unreachable")


def human_seconds(value) -> str:
    if value is None:
        return "—"
    if value >= 1:
        return f"{value:.3f} s"
    if value >= 1e-3:
        return f"{value * 1e3:.2f} ms"
    return f"{value * 1e6:.1f} µs"


def delta(baseline, comparison, formatter) -> str:
    if baseline is None or comparison is None:
        return "—"
    difference = comparison - baseline
    sign = "+" if difference > 0 else "−" if difference < 0 else ""
    percent = f"{difference / baseline * 100:+.1f}%" if baseline else "n/a"
    return f"{sign}{formatter(abs(difference))} ({percent})"


def spread(values: list[float]) -> str:
    """Half-range relative to the median: the noise floor for these samples."""
    if len(values) < 2:
        return "—"
    middle = statistics.median(values)
    if middle <= 0:
        return "—"
    return f"±{(max(values) - min(values)) / 2 / middle * 100:.1f}%"


def table(header: list[str], aligns: list[str]) -> list[str]:
    separator = ["---:" if align == "r" else "---" for align in aligns]
    return ["| " + " | ".join(header) + " |", "|" + "|".join(separator) + "|"]


# --------------------------------------------------------------------------
# Sections
# --------------------------------------------------------------------------

def memory_section(rows, refs, stage) -> list[str]:
    massif = [row for row in rows if row["source"] == "massif"]
    native = [row for row in rows if row["source"] == "time"]
    allocations = [row for row in rows if row["source"] == "instruments"]
    if not (massif or native or allocations):
        return []

    lines = ["## Memory", ""]

    if massif:
        lines += [
            "Massif measures allocated heap over the life of the process. `Peak` is the",
            "high-water mark; `Retained` is what was still allocated at the last snapshot,",
            "which for a run that stops after the stage is what the stage kept.",
            "",
        ]
        lines += table(["Ref", f"Peak ({stage})", "Retained", "Peak (fixture)",
                        "Retained (fixture)", "Stage peak", "Stage retained"],
                       ["l", "r", "r", "r", "r", "r", "r"])
        attributable = {}
        for ref in refs:
            peak = median_of(massif, ref=ref, stage=stage, metric="peak_total")
            retained = median_of(massif, ref=ref, stage=stage, metric="retained_total")
            base_peak = median_of(massif, ref=ref, stage="fixture", metric="peak_total")
            base_retained = median_of(massif, ref=ref, stage="fixture", metric="retained_total")
            stage_peak = peak - base_peak if peak is not None and base_peak is not None else None
            stage_retained = (retained - base_retained
                              if retained is not None and base_retained is not None else None)
            attributable[ref] = (stage_peak, stage_retained)
            lines.append(
                f"| `{ref}` | {human_bytes(peak)} | {human_bytes(retained)} "
                f"| {human_bytes(base_peak)} | {human_bytes(base_retained)} "
                f"| **{human_bytes(stage_peak)}** | **{human_bytes(stage_retained)}** |"
            )
        lines.append("")
        if len(refs) == 2:
            first, second = refs
            lines += [
                "Subtracting the fixture-only run leaves what the stage itself allocated,",
                "without R start-up, the data, or the parameter edits -- all identical",
                "across branches.",
                "",
                f"- Stage peak: {delta(attributable[first][0], attributable[second][0], human_bytes)}"
                f" for `{second}` versus `{first}`.",
                f"- Stage retained: {delta(attributable[first][1], attributable[second][1], human_bytes)}"
                f" for `{second}` versus `{first}`.",
                "",
            ]

        # With --trace-children one round covers R and everything it spawned.
        processes = [row for row in massif if row["metric"] == "process_peak_total"]
        if processes:
            lines += [
                "### Per-process detail", "",
                "Massif follows child processes, so a round produces one file per process.",
                "The summary above uses the largest peak; this is every process, so an",
                "unexpected number can be traced to the process that caused it.",
                "",
            ]
            lines += table(["Ref", "Stage", "Round", "File", "Peak", "Retained",
                            "Snapshots", "Peak snapshot", "Command"],
                           ["l", "l", "r", "l", "r", "r", "r", "r", "l"])
            seen = set()
            for row in processes:
                key = (row["ref"], row["stage"], row["round"], row["path"])
                if key in seen:
                    continue
                seen.add(key)

                def sibling(metric, path=row["path"], ref=row["ref"], rnd=row["round"]):
                    for other in massif:
                        if (other["metric"] == metric and other["path"] == path
                                and other["ref"] == ref and other["round"] == rnd):
                            return other["value"]
                    return ""

                try:
                    peak_value = float(row["value"])
                except (TypeError, ValueError):
                    peak_value = None
                retained_value = sibling("process_retained_total")
                command = str(sibling("process_command"))[:48] or "—"
                lines.append(
                    f"| `{row['ref']}` | {row['stage']} | {row['round']} "
                    f"| {row['path']} | {human_bytes(peak_value)} "
                    f"| {human_bytes(float(retained_value) if retained_value not in ('', None) else None)} "
                    f"| {sibling('process_snapshots') or '—'} "
                    f"| {sibling('process_peak_snapshot') or '—'} "
                    f"| `{command}` |"
                )
            lines.append("")

    if native:
        lines += ["Physical memory as the OS saw it, from `/usr/bin/time -l`.", ""]
        lines += table(["Ref", "Max RSS", "Peak footprint", "Elapsed", "Max RSS (fixture)"],
                       ["l", "r", "r", "r", "r"])
        for ref in refs:
            lines.append(
                f"| `{ref}` | {human_bytes(median_of(native, ref=ref, stage=stage, metric='maximum_rss'))} "
                f"| {human_bytes(median_of(native, ref=ref, stage=stage, metric='peak_footprint'))} "
                f"| {human_seconds(median_of(native, ref=ref, stage=stage, metric='elapsed_seconds'))} "
                f"| {human_bytes(median_of(native, ref=ref, stage='fixture', metric='maximum_rss'))} |"
            )
        lines.append("")

    if allocations:
        lines += ["Instruments allocation totals. `Persistent` is what was still held when",
                  "recording stopped; `transient` was allocated and freed.", ""]
        lines += table(["Ref", "Persistent", "Transient", "Allocated"], ["l", "r", "r", "r"])
        for ref in refs:
            lines.append(
                f"| `{ref}` | {human_bytes(median_of(allocations, ref=ref, metric='persistent_bytes'))} "
                f"| {human_bytes(median_of(allocations, ref=ref, metric='transient_bytes'))} "
                f"| {human_bytes(median_of(allocations, ref=ref, metric='allocated_bytes'))} |"
            )
        lines.append("")

        categories = OrderedDict()
        for row in allocations:
            if row["metric"].startswith("persistent_bytes:"):
                categories.setdefault(row["metric"].split(":", 1)[1], None)
        if categories:
            lines += ["Largest persistent categories:", ""]
            lines += table(["Category"] + [f"`{ref}`" for ref in refs],
                           ["l"] + ["r"] * len(refs))
            for category in list(categories)[:10]:
                metric = f"persistent_bytes:{category}"
                cells = [human_bytes(median_of(allocations, ref=ref, metric=metric)) for ref in refs]
                lines.append(f"| {category} | " + " | ".join(cells) + " |")
            lines.append("")

    return lines


def timing_section(rows, refs, stage) -> list[str]:
    timing = [row for row in rows if row["source"] == "timing"]
    if not timing:
        return []

    phases: list[str] = []
    for row in timing:
        if row["metric"] not in phases:
            phases.append(row["metric"])

    lines = [
        "## Timing", "",
        "Measured inside one R session with `bench::hires_time()`, so R start-up,",
        "package loading and the fixture are excluded. Medians are pooled across",
        "alternating rounds; a delta smaller than the spread is noise.",
        "",
    ]
    lines += table(["Phase"] + [f"`{ref}`" for ref in refs] + ["Spread", "Delta"],
                   ["l"] + ["r"] * len(refs) + ["r", "r"])

    baseline_ref = refs[0]
    for phase in phases:
        medians = {ref: median_of(timing, ref=ref, metric=phase) for ref in refs}
        cells = [human_seconds(medians[ref]) for ref in refs]
        label = f"**{phase}**" if phase == stage else phase
        change = (delta(medians[baseline_ref], medians[refs[1]], human_seconds)
                  if len(refs) == 2 else "—")
        lines.append(f"| {label} | " + " | ".join(cells)
                     + f" | {spread(numeric(timing, ref=baseline_ref, metric=phase))} | {change} |")
    lines.append("")

    ladder_phases = [phase for phase in LADDER if phase in phases]
    if "helper" in phases and ladder_phases:
        lines += [
            "### Ladder versus the end-to-end run", "",
            "`helper` is `fit_fims(optimize = TRUE)` timed as one call. The ladder phases",
            "decompose that same work, so the gap is what measuring stage by stage misses.",
            "",
        ]
        lines += table(["Ref"] + list(ladder_phases) + ["Ladder sum", "`helper`", "Unaccounted"],
                       ["l"] + ["r"] * (len(ladder_phases) + 3))
        for ref in refs:
            cells, total = [], 0.0
            for phase in ladder_phases:
                value = median_of(timing, ref=ref, metric=phase)
                if value is not None:
                    total += value
                cells.append(human_seconds(value))
            helper = median_of(timing, ref=ref, metric="helper")
            if helper:
                gap = helper - total
                unaccounted = f"{human_seconds(abs(gap))} ({gap / helper * 100:+.1f}%)"
            else:
                unaccounted = "—"
            lines.append(f"| `{ref}` | " + " | ".join(cells)
                         + f" | {human_seconds(total)} | {human_seconds(helper)} | {unaccounted} |")
        lines.append("")
    return lines


def cpu_section(rows, refs, platform_name) -> list[str]:
    cpu = [row for row in rows if row["source"] == "cpu"]
    if not cpu:
        return []

    profiler = "Instruments Time Profiler" if platform_name == "Darwin" else "Linux perf"
    lines = ["## CPU profile", "", f"Profiler: {profiler}.", ""]

    statuses = {row["ref"]: row["value"] for row in cpu if row["metric"] == "status"}
    symbols = [row for row in cpu if row["metric"].startswith("symbol:")]

    if not symbols:
        # An empty table would read as a result; say what happened instead.
        reasons = ", ".join(f"`{ref}`: {statuses.get(ref, 'unknown')}" for ref in refs)
        lines += [
            f"**No CPU profile was captured** ({reasons}).", "",
            "`unavailable` means the profiler is not installed, `disabled` means it was",
            "switched off with CPU_PROFILE=0, and `failed` means it ran but could not",
            "record -- on Linux usually /proc/sys/kernel/perf_event_paranoid.",
            "",
        ]
        return lines

    if statuses:
        lines.append("Capture status: "
                     + ", ".join(f"`{ref}`: {statuses.get(ref, 'unknown')}" for ref in refs) + ".")
        lines.append("")

    for ref in refs:
        ranked = sorted(
            ((row["metric"].split(":", 1)[1], float(row["value"]))
             for row in symbols if row["ref"] == ref),
            key=lambda item: item[1], reverse=True,
        )
        if not ranked:
            continue
        unit = "Samples" if platform_name == "Darwin" else "Overhead"
        total = sum(value for _, value in ranked) or 1.0
        lines += [f"### `{ref}`", ""]
        lines += table(["Rank", "Object", "Symbol", unit], ["r", "l", "l", "r"])
        for rank, (symbol, value) in enumerate(ranked, 1):
            dso, _, name = symbol.partition("::")
            if not name:
                dso, name = "", dso
            shown = f"{value / total * 100:.2f}%" if platform_name == "Darwin" else f"{value:.2f}%"
            lines.append(f"| {rank} | {dso} | `{name.replace('|', chr(92) + '|')}` | {shown} |")
        lines.append("")
    return lines


def signature_section(signatures) -> list[str]:
    if not signatures:
        return []
    lines = ["## Equivalence check", ""]
    if len(signatures) < 2:
        return lines + ["Only one ref recorded a signature; nothing to compare.", ""]

    refs = list(signatures)
    keys: list[str] = []
    for values in signatures.values():
        for key in values:
            if key not in keys and key not in {"ref", "fims_version"}:
                keys.append(key)

    mismatched = [key for key in keys
                  if len({signatures[ref].get(key, "") for ref in refs}) > 1]

    lines += table(["Key"] + [f"`{ref}`" for ref in refs] + ["Same"],
                   ["l"] + ["l"] * len(refs) + ["l"])
    for key in keys:
        cells = []
        for ref in refs:
            value = signatures[ref].get(key, "")
            cells.append(f"`{value[:60]}…`" if len(value) > 60 else (f"`{value}`" if value else "—"))
        lines.append(f"| {key} | " + " | ".join(cells) + " | "
                     + ("no" if key in mismatched else "yes") + " |")
    lines.append("")
    if mismatched:
        lines += [f"> **The branches did not do the same work** ({', '.join(mismatched)} differ). "
                  "Treat every comparison above as not comparable until this is explained.", ""]
    else:
        lines += ["Both branches produced identical results, so the comparisons hold.", ""]
    return lines


def read_signature(path: Path) -> "OrderedDict[str, str]":
    values: "OrderedDict[str, str]" = OrderedDict()
    if not path.exists():
        return values
    with path.open(encoding="utf-8", newline="") as stream:
        for row in csv.DictReader(stream, delimiter="\t"):
            key = row.get("key")
            if key:
                values[key] = row.get("value") or ""
    return values


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--results", type=Path, required=True)
    parser.add_argument("--signature", nargs=2, action="append", default=[],
                        metavar=("REF", "TSV"))
    parser.add_argument("--stage", default="")
    parser.add_argument("--teardown", default="")
    parser.add_argument("--build-type", default="")
    parser.add_argument("--platform", default="Linux")
    parser.add_argument("--run-id", default="")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    rows = read_rows(args.results)
    refs: list[str] = []
    for row in rows:
        if row["ref"] and row["ref"] not in refs:
            refs.append(row["ref"])

    signatures: "OrderedDict[str, OrderedDict[str, str]]" = OrderedDict()
    for ref, path in args.signature:
        values = read_signature(Path(path))
        if not values:
            continue
        if values.get("stage") == "helper":
            values = OrderedDict((key if key == "ref" else f"helper_{key}", value)
                                 for key, value in values.items())
        signatures.setdefault(ref, OrderedDict()).update(values)

    generated = dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat()
    lines = [
        f"# FIMS benchmark report{': ' + args.run_id if args.run_id else ''}",
        "",
        f"Generated: `{generated}`  ",
        f"Stage: `{args.stage}` | teardown: `{args.teardown}` | build type: "
        f"`{args.build_type}` | host: `{args.platform}`  ",
        f"Refs: {', '.join(f'`{ref}`' for ref in refs) if refs else '—'}",
        "",
    ]

    if not rows:
        lines += ["No measurements were collected. Check the `*_profile.log` files.", ""]
    else:
        lines += memory_section(rows, refs, args.stage)
        lines += timing_section(rows, refs, args.stage)
        lines += cpu_section(rows, refs, args.platform)
        lines += signature_section(signatures)
        lines += [
            "## Reading these numbers", "",
            "- Compare peaks only when both refs ran the same stage, fixture and build type.",
            "- Peak and retained answer different questions: the high-water mark of the",
            "  whole process, versus what was still held when it exited.",
            f"- Every number here comes from `{args.results.name}` in this directory, one",
            "  row per measurement, if you would rather do your own analysis.",
            "",
        ]

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text("\n".join(lines), encoding="utf-8")
    print(f"Report written to {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
