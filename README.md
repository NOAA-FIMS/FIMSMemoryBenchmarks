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

## Fixing Valgrind and perf installation

Both profilers can be installed and still not work, so `R/main.R` runs each one
against `/bin/true` before anything is compiled and stops with the failure
below. Either failing stops the analysis before anything is built: a profiler
that cannot record here fails every run the same way, so it is better to find
out in seconds than after the whole matrix. A CPU profile that still records
nothing once runs have started stops the run for the same reason.

**`valgrind is not on PATH`**

```bash
sudo apt install valgrind
```

**`unknown program massif-<arch>-linux`**

The `valgrind` command is only a launcher: it execs a separate tool binary per
architecture, and that binary is missing or unreachable.

```bash
which -a valgrind          # a conda or Homebrew valgrind earlier on PATH is
                           # the usual cause; it ships without tool binaries
dpkg -L valgrind | grep massif    # does the distro package have them?
echo $VALGRIND_LIB         # must be empty, or hold those tool binaries
sudo apt install --reinstall valgrind
```

**`Massif ran but wrote no output`**

The temporary directory is not writable, or the disk is full.

**`perf is not on PATH`**

```bash
sudo apt install linux-tools-common linux-tools-generic
```

On WSL2 that often installs a `perf` that refuses to run because it does not
match `uname -r`. WSL2 runs a custom kernel, so build perf from its source
instead:

```bash
git clone --depth 1 -b linux-msft-wsl-$(uname -r | cut -d- -f1) \
  https://github.com/microsoft/WSL2-Linux-Kernel.git
make -C WSL2-Linux-Kernel/tools/perf
# put the resulting perf binary on PATH
```

**`perf record recorded no samples`**

Usually permissions rather than missing hardware:

```bash
sudo sysctl kernel.perf_event_paranoid=1   # allow user-space sampling
sudo sysctl kernel.kptr_restrict=0         # let kernel symbols resolve
```

Make both permanent in `/etc/sysctl.conf`. If nothing records after that, the
kernel exposes no PMU and no usable software timer, and this host cannot produce
a CPU profile. Note that falling back to `cpu-clock` is not a failure: perf's
default is a hardware event that needs a PMU, which WSL2 and most VMs do not
have, and the run continues with the software event instead.

**Naming CPU symbols in libR.so**

Addresses like `0x000000000019c9e4` in the CPU table are functions inside R's
shared library, which distributions ship stripped. perf names what the library
exports and leaves its internal functions as addresses. The ranking is still
right; only those names are missing. Naming them needs R's debug symbols.

On WSL2 with Ubuntu, and R installed from Ubuntu's own archive:

```bash
sudo apt install ubuntu-dbgsym-keyring
echo "deb http://ddebs.ubuntu.com $(lsb_release -cs) main restricted universe multiverse
deb http://ddebs.ubuntu.com $(lsb_release -cs)-updates main restricted universe multiverse" \
  | sudo tee /etc/apt/sources.list.d/ddebs.list
sudo apt update
sudo apt install r-base-core-dbgsym
```

R installed from CRAN's Ubuntu repository has no matching debug package, so
there the addresses stay. The Codespaces image builds R from source; whether its
`libR.so` keeps symbols has not been checked.

## Running a comparison

Edit the settings at the top of `R/main.R` — the refs to compare, which runs to
make (`only`), how many back-to-back cycles, whether to include the heavy
rows — then:

```bash
Rscript R/main.R
```

Runs are named, and the name is the whole specification:
`[quadra-]<stage>-<size>[-<teardown>]`, as in `initialize-normal`,
`sdreport-large` or `initialize-normal-release`. Stage, size, teardown and
backend are read from it, and so are the profilers. `labels` lists every run the
comparison can make and `only` picks which of them to run this time; naming a
teardown row also runs the row without the teardown, since a teardown number
means nothing without one to compare it against.

Or call it directly from a session that has never loaded FIMS:

```r
source("R/run_benchmark.R")
run_fims_benchmark("main", "xptr-refactor", stage = "initialize")
```

`stage` is a rung of the ladder in `setup_fims_model()`: `initialize`, `tape`,
`evaluate`, `optimize`, `sdreport`, or `helper` for the end-to-end `fit_fims()`
path. The ladder is cumulative, so `sdreport` runs everything below it.
`initialize` includes `CreateTMBModel()`, which `initialize_fims()` calls, so the
derived quantities are already populated there.

`backend` is the second axis, and both refs always run the one you ask for.
`TMB` has both refs build a TMB tape and optimize it, so a difference is the
interface and nothing else. `quadra` fits through Quadra instead, which never
calls `TMB::MakeADFun` and so has no tape to stop at. Quadra therefore runs only
at the `helper` stage, through `fit_fims()`, and a run named for Quadra at any
other stage is refused rather than quietly run under TMB.

There is deliberately no fallback. A ref whose build does not provide the
Quadra API fails the run rather than quietly using TMB, because a comparison
of one branch's Quadra against another branch's TMB moves two variables at once
and answers no question worth asking. Compare a Quadra branch against a Quadra
baseline. Each ref still records which entry points it used, `xptr` or
`native`, and the reports print that.

Most comparisons do not involve Quadra, so `R/main.R` skips its rows unless you
name branches for them in `ref_first_quadra` and `ref_compare_quadra`. If your
baseline branch has the API, use the same two branches for both, and each
backend is then compared on identical code.

Every stage also gets a **reference run**: the stage once more per ref, on the
optimized build, with no profiler attached. Profilers are for attribution, and
they distort what a user of the branch would actually see, so that comes from
here:

- **Peak RSS**, read from the kernel's `VmHWM` on Linux and from
  `/usr/bin/time -l` on macOS, with page faults alongside.
- **Validation.** The parameter values the model holds at the end of the rung,
  compared between refs: `initialize_fims()` parameters at `initialize`, and
  `obj$env$parList()` at `tape` and `evaluate`. From `optimize` up, the fit and
  its estimates, with standard errors at `sdreport`. A Quadra run records its
  estimates through `get_fixed()` and `get_random()`, since it has no TMB object
  to read them from. At `sdreport` the normal size also records the random
  effects and the derived quantities, each with its standard error; the large
  size does not, since both grow with the number of years and two builds that
  agree at 30 years agree at 120.

Timing is deliberately not taken from it: a single run is noisy, and timing
belongs to `bench::mark()`, which repeats. A reference run that fails stops the
benchmark, since without it there is no peak RSS and no validation.

Every run at the normal size also gets **back-to-back runs**
(`run_model_for_R_profiler()` in `R/run_model_for_profilers.R`): the stage built,
run and torn down `bench_iterations` times in one process, then the same again
under `bench::mark()`. After each cycle it reads the memory still in use, R and
C++ together, from glibc's own count, after three garbage collections. Flat
after the first couple of cycles means nothing accumulates; a steady rise is a
leak, and the report gives its size per model built. Resident memory cannot show
this, because freed memory stays inside the process.

The cycle uses the run's own teardown, and every cycle starts by clearing
regardless, since `setup_fims_model()` does. So the teardown decides whether a
model is alive when the memory is read: the growth per cycle is the leak, and
the level is what the teardown did or did not return. `none` against `clear`
gives the size of a live model, and `release` says whether dropping the R
handles alone returned it. The memory half is Linux only; `bench::mark()`
supplies timing, R allocation and garbage collections everywhere.

Which profilers a run gets follows from its name. Every run is measured for
memory. A run without a teardown also gets the CPU profile, which a teardown row
skips because it would repeat its partner row and say nothing about memory
coming back. Leak checks and back-to-back runs are limited to the normal size,
where every row gets both: memcheck is far slower than Massif, many cycles of
the 120-year model would take far too long, and both leaks and accumulation show
up at either size.

## What a run produces

One document covers a whole analysis, not one per run. `R/main.R` writes
`outputs/<date>_report.md` from every run it completed, and each section
appears only where the runs produced that measurement, so an analysis of
`initialize` alone reports memory and says nothing about a fit. The same
numbers print to the terminal as each run finishes.

To rebuild it, or to report on runs from different days, pass the run
directories:

```bash
Rscript R/report.R outputs/report.md outputs/<run> outputs/<other run>
Rscript R/report.R --console outputs/<run>          # the short version only
```

Each run directory, `outputs/<date>_<ref>_vs_<ref>_<run name>/`, holds:

| File | Contents |
|---|---|
| `results.tsv` | Every measurement, one row each — what the report is built from |
| `manifest.tsv` | Settings used and per-profiler exit status |
| `reference_<ref>.rds` | What the reference run computed, saved whole |
| `run.log` | Everything the subprocesses printed |
| `massif_*`, `cpu_*` | Raw artifacts for `ms_print` and `perf report` |
| `Makevars.*` | The build flags that produced the results |

## How it works

```
R/main.R                    settings and preflight checks
  └─ run_fims_benchmark()   R/run_benchmark.R: setup, orchestration, reporting
       ├─ install           one library per ref per build type
       ├─ profile           scripts/memory.sh, scripts/performance.sh
       │                      └─ R/run_model_for_profilers.R
       │                           setup_fims_inputs()
       │                           wait for the recorder to attach
       │                           setup_fims_model()
       └─ collect           summarize_cpu.py, summarize_massif.py or
                            summarize_macos.py, check_leaks.py; each writes
                            tidy rows, merged by scripts/tidy.py into
                            results.tsv. Nothing renders a document here.
  └─ R/report.R             one report across every run, from those results.tsv
```

The summarizers parse artifacts into rows and nothing else in this flow, so
there are no intermediate Markdown files to keep in step. They can still render
their own report if you pass `--output`, which is useful when debugging one
profiler by hand.

Each ref is installed twice, into `outputs/.lib-cache/debug/<ref>` and
`outputs/.lib-cache/profile/<ref>`,
using `scripts/Makevars.debug` (`-O1`, for Valgrind's allocation attribution)
and `scripts/Makevars.profile` (`-O2`, so CPU profiles rank the code anyone
actually runs). Both keep `-g`, frame pointers, and default symbol visibility.
`R_MAKEVARS_USER` points at them, so `~/.R/Makevars` is never involved.

The model runs **once** per profiler. The inputs are built inside the profiled
process, and the recorder starts after it — `perf -D` and Instruments attach
during a short wait, so the data preparation stays out of the recording.
Valgrind instruments from the first instruction and cannot do this, which is
why every ref also gets an inputs-only baseline run: the report subtracts it to
report what the stage itself cost.

The shell scripts take one measurement each and can be run by hand. They decide
only the profiler; the model settings reach `run_model_for_cpp_profiler()` as
environment variables, which is why they are set on the command line here:

```bash
R_LIBS=outputs/.lib-cache/debug/main FIMS_STAGE=initialize FIMS_SIZE=normal \
  scripts/memory.sh --tool massif --out /tmp/one.out
```

## Notes

- `--trace-children=yes` is required, not optional. `Rscript` is a launcher
  that execs the real R binary, and without it Valgrind stops at the exec and
  writes no output at all. It also means one Massif file per process, so
  `summarize_massif.py` takes the largest peak.
- Massif runs with its default `--threshold`. Setting it to 0 keeps every entry
  in every detailed snapshot tree, which on R plus TMB stacks produced output
  files approaching a gigabyte per process.
- Low optimization is slow on Eigen and TMB templates, and Valgrind multiplies
  that. `scripts/Makevars.debug` uses `-O1` as the compromise; `-O0` attributes
  allocations best but can make the large model impractical.
- Two FIMS builds cannot be loaded into one R process, so every comparison is
  made across separate processes.

## Tests

```bash
PYTHONPATH=scripts python3 -m unittest discover -s scripts -p "test_*.py"
Rscript scripts/test_multi_refs.R
Rscript scripts/test_reference_rows.R
Rscript scripts/test_model_functions.R
```

| Test | Covers |
|---|---|
| `test_parsers.py` | The Massif and perf parsing the benchmark depends on |
| `test_check_leaks.py` | The leak log parser |
| `test_report.py` | `R/report.R`: each section appears when its measurement is there and not otherwise |
| `test_reference_rows.R` | The reference run's values turned into rows, in the shape `setup_fims_model()` records, rendered through to the report |
| `test_model_functions.R` | `setup_fims_model()` and both functions in `R/run_model_for_profilers.R`, including detecting a leak |
| `test_multi_refs.R`, `test_multi_reports.py` | Ref handling, and the hand-run `--output` reports |

None of them need FIMS installed. `test_model_functions.R` installs a stand-in,
`scripts/stub_fims`, into a temporary library; it covers the initialize rung,
since the rungs above it need TMB's compiled tape.

## To do

- **Where R spends its time.** `bench::mark()` now says how long each stage
  takes, but not which R functions the time goes to. At `initialize` the CPU
  profile shows the time is in R's evaluator, so Rprof with `profvis` is the
  next tool.
- **Rprof and jointprof**, for R-level and mixed R/C++ call stacks.
  `scripts/run_pprof_linux.sh` holds the gperftools recipe as a reference for
  this work; `profiles = "r"` is not implemented.
- **Scalability reporting.** `setup_fims_inputs(size = "large")` builds the
  120-year model and `results.tsv` carries a `size` column, but nothing yet
  renders cost against size; that comparison is still done by hand.
- **`scripts/test_multi_refs.R` needs FIMS installed** only if you extend it
  past ref handling; as written it checks `resolve_refs()` and runs anywhere.
- **Installed builds are cached** in `outputs/.lib-cache/<build type>/<ref>`,
  keyed by the commit the ref resolves to. Nothing prunes that cache, and the
  key does not capture a `Makevars` edit, so delete the entry when you change
  build flags for a commit you have already installed.
- **The macOS path is untested.** Instruments capture, the allocation statistics
  export, and `/usr/bin/time -l` parsing have only been exercised with stubs.
