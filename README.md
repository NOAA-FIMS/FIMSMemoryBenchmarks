# FIMSMemoryBenchmarks

A repository to benchmark and compare the memory footprint of NOAA-FIMS/FIMS builds.

## Repository Layout

- `/R`: Helper R scripts for setup and benchmark stage execution.
- `/scripts`: Shell runners for memory profiling tools.
- `/outputs`: Benchmark and profiler outputs (`.gitkeep` included).
- `/.devcontainer`: Codespaces setup for reproducible profiling builds.

## Optimized Profiling Build Configuration

Benchmarks use the repository-owned `config/Makevars.profile` with:

- `-O2` optimization
- `-g` symbols for native profilers
- `-fno-omit-frame-pointer` for reliable stack unwinding

The runner sets `R_MAKEVARS_USER` only while installing FIMS, so results do not
depend on a developer's personal Makevars file. `DEVTOOLS_LOAD=1` prevents the
FIMS package from selecting its install-time stripping/LTO configuration.

## Install FIMS for Profiling

`R/setup_FIMS` provides:

```r
install_fims_profile(ref = "main")
```

It installs `NOAA-FIMS/FIMS` from GitHub for a chosen branch/tag/commit using source compilation.

## Maintainability metrics

Set up the isolated source analyzer once:

```bash
python3 -m venv .venv-maintainability
.venv-maintainability/bin/pip install -r scripts/requirements-maintainability.txt
```

The runner uses that environment automatically, or an interpreter selected with
`MAINTAINABILITY_PYTHON`. After profiling each branch, it downloads the source
archive for the installed package's `RemoteSha` and analyzes that exact commit.
Source analysis is outside the build, runtime, and RSS measurements. If the
analyzer, commit metadata, or source download is unavailable, it records an
explicit unavailable result without aborting the performance benchmark.

`maintainability_report.md`, per-branch `maintainability_<ref>.json`, the final
report, management summary, and console table include:

- R and C++ file counts and non-comment source lines (NLOC), reported separately.
- Function counts and cyclomatic complexity: median, nearest-rank p95, maximum,
  and the count above 15.
- Function-size distributions and the highest-complexity functions with paths
  and line numbers. JSON also records functions exceeding 100 NLOC.
- Lizard's duplicated-token percentage, with a 70-token minimum match.
- A path-based estimate of adapter/interface NLOC, with matching files in JSON.
- A 0–100 lexical Maintainability Index (MI) estimate per file, with NLOC-weighted
  and equal-file averages, per-language results, lower-tail scores, scoring coverage,
  and the share of code in files below MI 20. Higher MI is better under this method.
- Lowest-MI file hotspots with raw inputs, and same-path changes against the first
  branch using fixed baseline NLOC weights. Added/removed files are counted separately.

Analysis is limited to `R/`, `src/`, and `inst/include/`. Vendored directories
(including Quadra, Eigen, LBFGSpp, and external), generated bindings and files
marked as generated, tests, and examples are excluded. JSON inventories include
file hashes, language, scope, duplicate groups, and per-function metrics so the
classification can be audited. Local-source scans describe the working tree;
only downloaded commit archives establish the installed-revision match.

Branch coverage requires instrumented tests and is **not measured** here.
Cognitive complexity, semantic coupling, and static-analysis findings are also
explicitly unmeasured. Adapter NLOC is
an estimate based on paths, not a coupling score. Review flags are not quality
verdicts; compare like-for-like language and source scope. Metric definitions
follow the pinned [Lizard analyzer](https://github.com/terryyin/lizard).

The versioned MI method (`lexical-file-mi-v1`) uses the
[Microsoft formula](https://learn.microsoft.com/en-us/visualstudio/code-quality/code-metrics-maintainability-index-range-and-meaning):

```text
MI = max(0, (171 - 5.2 ln(V) - 0.23 G - 16.2 ln(L)) * 100 / 171)
V = (total operators + total operands) * log2(distinct operators + distinct operands)
G = sum of Lizard function cyclomatic complexity within the file
L = file NLOC
```

Halstead counts use the pinned lexer: keywords and punctuation are operators;
identifiers, function names, and literals are operands. Comments and C++
preprocessor directives are excluded from volume. Macros are not expanded and
C++ template syntax is not semantically resolved. All raw counts are in JSON.
This is an **estimate**, not an implementation of Visual Studio's analyzer.
There is no comment bonus, and zero-volume/empty files are unscored. Top-level
logic and parser limitations can undercount complexity. Parser warnings make a
result partial; old JSON without MI shows “Not measured” until reanalyzed.

Overall MI is the NLOC-weighted mean of file scores, not a score computed from
concatenated branch totals. Equal-file averages and separate R/C++ results expose
sensitivity to file organization and language mix. The below-20 share is a review
aid, not a calibrated quality threshold. Duplication, test coverage and coupling
are not ingredients of this formula; they remain separate evidence. File splits,
removed functionality and vendored code can improve MI without reducing the
maintenance effort of the complete system. Use same-path comparisons and inspect
hotspots before declaring a branch more maintainable. See also
[Halstead definitions and MI limitations](https://radon.readthedocs.io/en/master/intro.html).

To inspect a local checkout without rebuilding FIMS:

```bash
.venv-maintainability/bin/python scripts/maintainability.py \
  --source /path/to/FIMS --ref my-branch --output /tmp/maintainability.json
.venv-maintainability/bin/python scripts/maintainability.py \
  --report /tmp/maintainability.json --output /tmp/maintainability_report.md
```

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

The runner uses the 120-year `large` wrapper model by default. Retain the
original 30-year baseline with `MODEL_SIZE=medium`:

```bash
MODEL_SIZE=medium bash scripts/run_massif.sh
```

You can also run the comparison from R. The function invisibly returns the new
output directory:

```r
source("R/main.R")
report_dir <- compare_fims_branches(
  ref_first = "main",
  ref_compare = "remove-direct-rcpp",
  model_size = "large"
)
```

Compare any number of branches with a character vector:

```r
report_dir <- compare_fims_refs(
  refs = c("update-R-with-XPtr-interface", "dev-xptr-quadra", "dev-native-quadra"),
  model_size = "large"
)
```

The first ref is the baseline. Each additional ref gets its own validation,
memory, runtime, and leak results in the same output directory; comparisons are
against that baseline. Duplicate refs run once, preserving order. A single ref
is also supported. The original two-ref function remains available.

The shell runner accepts the same ordered list as positional arguments:

```bash
bash scripts/run_massif.sh main dev-xptr-quadra dev-native-quadra
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
- A `joint_validation_report.md` comparison of objective values, gradients,
  optimized parameters, convergence status, iterations, and `nlminb`
  objective/gradient evaluation counts.
- A combined `final_report.md` with the model description, side-by-side
  parameter estimates, joint validation, CPU profile, and memory profile.
- A one-page `management_summary.md` with decision-relevant findings,
  validation evidence, performance highlights, and the recorded build profile.

Both Markdown reports include a metric-by-metric branch comparison with absolute
and percentage deltas. When Instruments statistics are available, the macOS
report also compares persistent and transient allocation totals and highlights
the ten allocation categories with the largest persistent-memory changes. It
also attributes persistent bytes for both branches to TMB/TMBad, Quadra, Rcpp,
the R runtime, FIMS C++, or system/unresolved symbols.

On Linux, child processes are profiled separately. The Markdown summary uses
the process with the highest total peak for each ref and lists all process
profiles. It classifies leaf bytes from the peak Massif allocation tree into
the same origin groups using each allocation's complete stack path. Use
`ms_print` on an individual `.out.<pid>` file to inspect its allocation tree.

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

Each branch's validation run now records total wall-clock runtime in
`joint_validation_<ref>_<version>.rds.runtime_seconds`. A monotonic timer wraps
the entire R process, including startup, package loading, model/tape setup,
initial evaluation, joint optimization, final evaluation, and saving results.
Branch installation and the separate profiling runs are excluded. The joint
validation, final, and management reports show total runtime alongside the
optimization-only timing. Older runs show `Not recorded` for total runtime;
their separate memory-workload timings cannot supply this measurement.

The runner finishes with a console comparison of peak RSS and total validation
runtime for each branch, including absolute and percentage changes relative to
the first branch. RSS comes from the separate macOS `inner` workload; runtime
comes from the complete joint-validation process. Missing measurements show
`Not recorded`. Linux currently collects Massif heap usage rather than peak RSS,
so its console model-run RSS comparison is unavailable.

The console also includes build peak process RSS and leaked/lost bytes for each
branch. Installation is wrapped in `/usr/bin/time` (`-l` on macOS, GNU `-v` on
Linux), with the raw measurement saved as `build_profile_<ref>.txt`. This is the
OS-reported maximum per-process RSS, not the sum of simultaneous compiler
processes. It covers the installation command, including build and package load
checks. Linux requires GNU time at `/usr/bin/time`.

Leak totals come from each branch's leak-check JSON. On macOS this is reported
leaked bytes; on Linux it sums definitely, indirectly, and possibly lost bytes,
excluding reachable and suppressed allocations. The console includes check
status so unavailable or failed measurements cannot be mistaken for zero leaks.

Backend selection for validation, evaluation, fitting, and uncertainty reporting
prefers the XPtr Quadra API (`quadra_evaluate`, `quadra_fit`, `quadra_sdreport`),
then the `native_quadra_*` API, then legacy Quadra, and finally TMB. A modern
API is selected only when all three functions exist in the FIMS namespace.
The `dev-xptr-quadra` branch is recorded as backend `xptr` in validation results.
The `helper` mode continues to delegate backend selection to FIMS's `fit_fims`.

When XPtr Quadra exports `quadra_objective()` and `quadra_gradient()`, or native
Quadra exports `native_quadra_objective()` and `native_quadra_gradient()`, joint
validation uses those separate `nlminb` callbacks: objective-only requests use
forward-only tape replay, and gradient requests reuse that forward pass when
parameters match exactly. Repeated gradients reuse the last reverse pass. Older
Quadra builds retain the combined-evaluation fallback. TMB validation also uses
its separate `fn` and `gr` callbacks. Initial/final validation diagnostics still
use the combined evaluator, and Quadra's combined API remains available.

Leak detection runs separately for each branch by default (`LEAK_CHECK=0` disables
it). macOS uses `leaks --atExit` with allocation stack logging; Linux uses Valgrind
Memcheck with full leak checking. Each runs the joint-validation workload,
collects R garbage, and checks at exit. Detector overhead is excluded from the
total runtime measurement. This can substantially increase benchmark duration.
`leak_report.md`, the final report, and the management summary show the status
and detected bytes, with per-branch JSON records and raw logs for allocation
stacks. Failed or unavailable checks are explicitly distinguished from zero
detected leaks. Reports include allocations from R and dependencies, and do not
treat still-reachable memory as a leak or prove absence of repeated-run growth.

Leak reports also summarize allocation origins (TMB/TMBad, Quadra, Rcpp, R,
FIMS with an unspecified backend, or system/other/unresolved). They show the
largest leak records, allocation callers, source locations when symbols provide
them, and raw-log line numbers. Per-branch JSON retains full parsed stacks.
Attribution uses the nearest recognizable allocation caller; it does not prove
which component lost ownership. Parsed byte coverage is checked against detector
totals, and unavailable stacks remain explicit. Memcheck's combined direct and
indirect totals are separated to avoid counting indirect losses twice.
