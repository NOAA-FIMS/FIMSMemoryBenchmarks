# FIMSMemoryBenchmarks

Compare the memory and CPU cost of two [NOAA-FIMS/FIMS](https://github.com/NOAA-FIMS/FIMS)
builds. Each branch is installed from source, one rung of the FIMS interface
ladder is profiled under Valgrind and `perf` (or Instruments on macOS), and the
results are collected into one table and one report.

## Requirements

- R with `remotes`, `bench`, `dplyr`, `tidyr`, and FIMS's own dependencies
- `python3` for the collector and reporter
- Linux: `valgrind`, `perf` for CPU profiles, and GNU `time` (`apt install
  time`) if you want build cost recorded
- macOS: Xcode, for `xctrace`

Keep **no FIMS installed in your user or site library**. Each run installs the
builds it needs into its own directories; a copy elsewhere is a silent fallback
that a half-finished install could quietly measure instead.

## Running a comparison

Edit the settings at the top of `R/main.R` — the refs, the stage, the teardown
mode, which profilers to run — then:

```bash
Rscript R/main.R
```

Or call it directly from a session that has never loaded FIMS:

```r
source("R/run_benchmark.R")
run_fims_benchmark("main", "xptr-refactor", stage = "initialize")
```

`stage` is a rung of the ladder in `setup_fims_model()`: `initialize`,
`assemble`, `tape`, `evaluate`, `optimize`, `sdreport`, or `helper` for the
end-to-end `fit_fims()` path. The ladder is cumulative, so `sdreport` runs
everything below it.

## What a run produces

In `outputs/<date>_<ref>-<version>_vs_<ref>/`:

| File | Contents |
|---|---|
| `report.md` | Memory table, per-process detail, CPU symbols, equivalence check |
| `results.tsv` | Every measurement, one row each — the input for your own analysis |
| `manifest.tsv` | Settings used and per-profiler exit status |
| `run.log` | Everything the subprocesses printed |
| `massif_*`, `cpu_*` | Raw artifacts for `ms_print` and `perf report` |
| `lib/`, `Makevars.*` | The builds and flags that produced the results |

For the metrics the report leaves out — heap breakdown, paging, allocation
categories, measurement coverage — with an explanation of each:

```bash
Rscript R/additional_report_metrics.R          # newest run, or pass a run directory
```

## How it works

```
R/main.R                    settings and preflight checks
  └─ run_fims_benchmark()   R/run_benchmark.R: setup, orchestration, reporting
       ├─ install           one library per ref per build type
       ├─ profile           scripts/memory.sh, scripts/performance.sh
       │                      └─ R/run_stage.R
       │                           setup_fims_inputs()
       │                           wait for the recorder to attach
       │                           setup_fims_model()
       └─ report            summarize_cpu.py, summarize_massif.py or
                            summarize_macos.py, summarize_validation.R,
                            check_leaks.py, then final_report.R and
                            management_summary.R; each also emits tidy rows,
                            merged by scripts/tidy.py into results.tsv
```

Each ref is installed twice, into `lib/debug/<ref>` and `lib/profile/<ref>`,
using `scripts/Makevars.debug` (`-O0`, for Valgrind's allocation attribution)
and `scripts/Makevars.profile` (`-O2`, so CPU profiles rank the code anyone
actually runs). Both keep `-g`, frame pointers, and default symbol visibility.
`R_MAKEVARS_USER` points at them, so `~/.R/Makevars` is never involved.

The model runs **once** per profiler. The fixture is built inside the profiled
process, and the recorder starts after it — `perf -D` and Instruments attach
during a short wait, so the data preparation stays out of the recording.
Valgrind instruments from the first instruction and cannot do this, which is
why every ref also gets a fixture-only baseline run: the report subtracts it to
report what the stage itself cost.

The shell scripts take one measurement each and can be run by hand:

```bash
scripts/memory.sh --tool massif --lib outputs/<run>/lib/debug/main \
  --stage initialize --out /tmp/one.out
```

## Notes

- `--trace-children` is off. TMB's C++ runs inside the R process, in a shared
  library, so it is already instrumented; tracing children only profiled the
  helper processes R spawns at start-up.
- Massif runs with its default `--threshold`. Setting it to 0 keeps every entry
  in every detailed snapshot tree, which on R plus TMB stacks produced output
  files approaching a gigabyte per process.
- `-O0` is slow on Eigen and TMB templates, and Valgrind multiplies it. If a run
  is impractical, `-Og` in `scripts/Makevars.debug` keeps most of the speed.
- Two FIMS builds cannot be loaded into one R process, so every comparison is
  made across separate processes.

## Tests

```bash
PYTHONPATH=scripts python3 -m unittest discover -s scripts -p "test_*.py"
Rscript scripts/test_multi_refs.R
Rscript scripts/test_quadra_backend.R
```

`test_check_leaks.py` and `test_console_summary.py` cover the leak parser and the
console summary, `test_multi_reports.py` covers ref resolution and N-ref
rendering, `test_multi_refs.R` covers `resolve_refs()`, and
`test_quadra_backend.R` covers backend selection. None of them need FIMS
installed.

## To do

- **R-level profiling.** Nothing measures wall-clock time yet; that belongs in R
  with `bench::mark()`, which also reports GC and R-level allocation. Such a
  script must: set `.libPaths()` to `lib/profile/<ref>` **before** `library(FIMS)`
  (the `-O2` build, not `-O0`); run one session per ref, because two builds
  cannot coexist in one process; and write rows in the `results.tsv` shape, which
  `collect.py --tidy` merges and `report.py` then reports.
- **Rprof and jointprof**, for R-level and mixed R/C++ call stacks.
  `scripts/run_pprof_linux.sh` holds the gperftools recipe as a reference for
  this work; `profiles = "r"` is not implemented.
- **Scalability reporting.** `setup_fims_inputs(size = "large")` builds the
  120-year model and `results.tsv` carries a `size` column, but nothing yet
  renders cost against size; that comparison is still done by hand.
- **Back-to-back runs.** Run the model K times in one session, recording elapsed
  time, `gc()` and RSS per iteration, to see whether memory or time grows. This
  is the direct test of the `clear` and `release` teardown modes.
- **`scripts/test_multi_refs.R` needs FIMS installed** only if you extend it
  past ref handling; as written it checks `resolve_refs()` and runs anywhere.
- **Validation results are cached** in `outputs/.validation-cache`, keyed by ref,
  commit and size, so every memory run can compose `final_report.md` without
  re-fitting. Nothing prunes that cache; delete it when the builds change under
  you in ways the commit does not capture (a Makevars edit, say).
- **The macOS path is untested.** Instruments capture, the allocation statistics
  export, and `/usr/bin/time -l` parsing have only been exercised with stubs.
