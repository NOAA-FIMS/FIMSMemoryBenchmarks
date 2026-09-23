"""R/report.R, rendered from small hand-written results.tsv files.

The report reads rows and nothing else, so these tests write rows with the
metric names the pipeline produces and check which sections appear. A section
must appear when its measurement is there and be absent when it is not, which
is where the report has broken before: renamed metrics, a renamed source.
"""
from pathlib import Path
import subprocess
import tempfile
import unittest

from tidy import write_rows

REPO_ROOT = Path(__file__).resolve().parent.parent
REFS = ("main", "xptr")


def rows_for(run_axes, measurements):
    """One row per (source, metric, ref-specific values)."""
    rows = []
    for source, metric, unit, values in measurements:
        for ref, value in zip(REFS, values):
            rows.append(dict(run_axes, ref=ref, fims_version="0.10.0", source=source,
                             metric=metric, unit=unit, value=value))
    return rows


def write_run(parent, label, stage, size, measurements):
    run = Path(parent) / label
    run.mkdir()
    axes = {"stage": stage, "backend": "TMB", "teardown": "none", "size": size}
    write_rows(run / "results.tsv", rows_for(axes, measurements))
    (run / "manifest.tsv").write_text(f"run_id\tlabel\tstage\n{label}\t{label}\t{stage}\n")
    return run


MASSIF = [
    ("massif", "stage_peak", "bytes", (85680000, 216)),
    ("massif", "peak_total", "bytes", (308932608, 224800000)),
    ("massif", "inputs_peak", "bytes", (223261000, 224800000)),
    ("massif", "stage_retained", "bytes", (90660000, 115000)),
    ("massif", "peak_heap", "bytes", (307900000, 224040000)),
    ("massif", "peak_extra", "bytes", (985000, 757000)),
    ("massif", "peak_stacks", "bytes", (0, 0)),
    ("massif", "retained_total", "bytes", (308900000, 219200000)),
    ("massif", "snapshots", "count", (59, 97)),
    ("massif", "processes", "count", (3, 3)),
]
EVERYTHING_ELSE = [
    ("reference", "maximum_rss", "bytes", (325435392, 239468544)),
    ("reference", "page_reclaims", "count", (77218, 56299)),
    ("reference", "page_faults", "count", (0, 0)),
    ("reference", "n_fixed", "count", (49, 49)),
    ("reference", "n_random", "count", (29, 29)),
    ("reference", "parameter:1:p1", "value", (2, 2)),
    ("reference", "parameter:2:p2", "value", (1, 1)),
    ("reference", "random_estimate:1:re", "value", (0.01, 0.0103)),
    ("reference", "random_error:1:re", "value", (0.004, 0.004)),
    ("reference", "derived_estimate:1:SSB", "value", (1000, 1000.5)),
    ("reference", "derived_error:1:SSB", "value", (40, 40)),
    ("lifecycle", "cycles", "count", (20, 20)),
    ("lifecycle", "heap_growth_per_cycle", "bytes", (0, 1048576)),
    ("lifecycle", "median_time", "seconds", (1.25, 0.9)),
    ("lifecycle", "gc_per_cycle", "count", (3, 2)),
    ("cpu", "status", "text", ("captured", "captured")),
    ("cpu", "symbol:Rf_findVarInFrame3", "percent", (9.55, 9.5)),
    ("cpu", "library:libR.so", "percent", (95.03, 93.46)),
    ("cpu", "library:FIMS.so", "percent", (0.14, 0.1)),
    ("build", "peak_rss", "bytes", (2738000000, 2738400000)),
]


def render(*runs, console=False):
    with tempfile.TemporaryDirectory() as directory:
        output = Path(directory) / "report.md"
        command = ["Rscript", str(REPO_ROOT / "R" / "report.R")]
        command += ["--console"] if console else [str(output)]
        command += [str(run) for run in runs]
        result = subprocess.run(command, capture_output=True, text=True)
        if result.returncode != 0:
            raise AssertionError(result.stderr)
        return result.stdout if console else output.read_text()


def headings(text):
    return {line for line in text.splitlines() if line.startswith("## ")}


class ReportSections(unittest.TestCase):
    def test_every_section_appears_when_its_measurement_is_there(self):
        with tempfile.TemporaryDirectory() as directory:
            run = write_run(directory, "initialize-normal", "initialize", "normal",
                            MASSIF + EVERYTHING_ELSE)
            found = headings(render(run))
        for heading in ("## Summary", "## The model",
                        "## Memory the stage is responsible for",
                        "## Peak heap of the whole process", "## The inputs baseline",
                        "## Memory still held at exit", "## What the peak was made of",
                        "## How well the run was sampled", "## Detailed branch comparison",
                        "## Back-to-back runs", "## Parameter values: initialize-normal",
                        "## Random effects: initialize-normal",
                        "## Derived quantities: initialize-normal",
                        "## Where the CPU time goes",
                        "## Where the CPU time goes, by library", "## Build cost",
                        "## Interpretation notes"):
            self.assertIn(heading, found)

    def test_sections_without_their_measurement_are_left_out(self):
        with tempfile.TemporaryDirectory() as directory:
            run = write_run(directory, "initialize-large", "initialize", "large", MASSIF)
            found = headings(render(run))
        self.assertIn("## Memory the stage is responsible for", found)
        for heading in ("## Summary", "## The model", "## Do the refs agree?",
                        "## Random effects: initialize-large",
                        "## Derived quantities: initialize-large",
                        "## Back-to-back runs", "## Where the CPU time goes",
                        "## Leaks at process exit", "## Build cost"):
            self.assertNotIn(heading, found)

    def test_a_cpu_profile_with_no_samples_is_said_rather_than_silent(self):
        failed = [("cpu", "status", "text", ("failed", "failed"))]
        with tempfile.TemporaryDirectory() as directory:
            run = write_run(directory, "initialize-normal", "initialize", "normal",
                            MASSIF + failed)
            text = render(run)
        self.assertIn("No CPU profile recorded any samples", text)

    def test_runs_become_rows_of_one_document(self):
        with tempfile.TemporaryDirectory() as directory:
            normal = write_run(directory, "initialize-normal", "initialize", "normal", MASSIF)
            large = write_run(directory, "initialize-large", "initialize", "large", MASSIF)
            text = render(normal, large)
        self.assertIn("2 runs comparing", text)
        section = text.split("## Memory the stage is responsible for", 1)[1].split("\n## ", 1)[0]
        self.assertIn("| initialize-normal |", section)
        self.assertIn("| initialize-large |", section)

    def test_console_summary(self):
        with tempfile.TemporaryDirectory() as directory:
            run = write_run(directory, "initialize-normal", "initialize", "normal",
                            MASSIF + EVERYTHING_ELSE)
            text = render(run, console=True)
        for label in ("Stage-attributable peak", "Peak RSS (reference run)",
                      "Memory growth per cycle", "Median time per cycle"):
            self.assertIn(label, text)


if __name__ == "__main__":
    unittest.main()
