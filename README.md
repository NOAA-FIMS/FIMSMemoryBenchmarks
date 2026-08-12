# FIMSMemoryBenchmarks

A repository to benchmark and compare the memory footprint of NOAA-FIMS/FIMS builds.

## Repository Layout

- `/R`: Helper R scripts for setup and benchmark stage execution.
- `/scripts`: Shell runners for memory profiling tools.
- `/outputs`: Benchmark and profiler outputs (`.gitkeep` included).
- `/.devcontainer`: Codespaces setup for debug-safe R compilation flags.

## Debug Build Configuration in Codespaces

This repository includes `.devcontainer/postCreate.sh`, which configures `~/.R/Makevars` with:

- `PKG_CXXFLAGS += -g -O0 -fno-omit-frame-pointer -fvisibility=default`
- `PKG_STRIP = true`

These settings preserve symbols and frame pointers for profiler-friendly builds.

## Install FIMS in Debug Mode

`R/setup_FIMS` provides:

```r
install_fims_debug(ref = "main")
```

It installs `NOAA-FIMS/FIMS` from GitHub for a chosen branch/tag/commit using source compilation.

## Benchmark Stages

`R/run_benchmark.R` is structured into five stages:

1. Static model construction through `MakeADFun()`
2. Single evaluation calls (`obj$fn()` and `obj$gr()`)
3. Full optimization run with `nlminb` (without `sdreport`)
4. Full optimization run with `nlminb` and `sdreport`
5. Cleanup and retention check via `TMB::FreeADFun(obj)` and `gc()`

> Before sourcing `R/run_benchmark.R`, define `fims_stage1_builder()` so it returns the stage-1 `MakeADFun()` object.

## Run Memory Benchmarks

```bash
bash scripts/run_massif.sh
```

By default this compares `main` with `xptr-refactor`. Override either ref without
editing the script:

```bash
REF_FIRST=main REF_COMPARE=my-feature-branch bash scripts/run_massif.sh
```

You can also run the comparison from R. The function invisibly returns the new
output directory:

```r
source("R/main.R")
report_dir <- compare_fims_branches(
  ref_first = "main",
  ref_compare = "remove-direct-rcpp"
)
```

The script detects the host operating system. On Linux it runs Valgrind Massif.
On macOS it records the Apple Instruments Allocations template with `xctrace`
and uses `/usr/bin/time -l` for peak RSS and memory-footprint measurements.

Each run generates:

- A timestamped `outputs/<run-id>/` directory, so repeated runs do not mix data
- On Linux, Massif output files, Valgrind logs, and `valgrind_massif_report.md`
- On macOS, Instruments `.trace` bundles, exported allocation XML, native
  resource profiles, and `macos_memory_report.md`
- On both platforms, native sampled CPU profiles and `cpu_profile_report.md`.
  macOS uses Instruments Time Profiler; Linux uses `perf` when installed.

Both Markdown reports include a metric-by-metric branch comparison with absolute
and percentage deltas. When Instruments statistics are available, the macOS
report also compares persistent and transient allocation totals and highlights
the ten allocation categories with the largest persistent-memory changes.

On Linux, child processes are profiled separately. The Markdown summary uses
the process with the highest total peak for each ref and lists all process
profiles. Use `ms_print` on an individual `.out.<pid>` file to inspect its
allocation tree.

The macOS report compares maximum resident set size and also records Apple's
peak-memory-footprint metric, timing, paging, and swap data. These physical-memory
metrics are broader than Massif heap usage, so results should only be compared
within the same operating system and profiler type.

The `.trace` bundles contain the closest macOS equivalent to Massif's detailed
allocation data: allocation lifetimes, persistent and transient bytes, types,
counts, and stack traces. Open them in Instruments for interactive analysis. The
script also exports the Allocations Statistics table as XML for automation.

Instruments requires Xcode and permission for the calling application under
**System Settings → Privacy & Security → Developer Tools**. If capture is denied,
the script reports the failure and still completes the RSS/footprint benchmark.
Set `MACOS_INSTRUMENTS=0` to intentionally skip Instruments capture.

The runner starts R with a short delay and attaches Instruments to its live
process, avoiding a race with the `Rscript` launcher. The defaults can be tuned
for unusually slow hosts or long benchmarks with
`FIMS_INSTRUMENTS_ATTACH_DELAY=10` (seconds) and
`INSTRUMENTS_TIME_LIMIT=60m`.

CPU profiling is enabled by default. Set `CPU_PROFILE=0` to skip it. Linux hosts
need the platform's `perf` package and permission to collect performance events.
