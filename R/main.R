# Single-model comparison: one fixture, one model run, two FIMS refs, measured
# for both memory and performance.
#
#   Rscript R/main.R
# or edit the settings below and
#   source("R/main.R")
#
# Sourcing this file runs the benchmark. The work lives in run_fims_benchmark()
# (R/run_benchmark.R), which drives scripts/memory.sh and scripts/performance.sh.
#
# IMPORTANT: use an R session that has never loaded FIMS. Installing a different
# build over a mapped DLL is unreliable.

# ---- settings ---------------------------------------------------------------

ref_first <- "main"
ref_compare <- "xptr-refactor"

# The ladder is cumulative, so "sdreport" times every phase in one pass:
# initialize, assemble, tape, evaluate, optimize, sdreport. Use "initialize" to
# spend the whole run on interface construction.
stage <- "sdreport"

# "none" leaves the interface objects alive, so the heap at exit is what the run
# retained. "clear" and "release" test whether that memory is returned.
teardown <- "none"

profiles <- c("memory", "cpu")

repo_root <- normalizePath(
  if (requireNamespace("here", quietly = TRUE)) here::here() else getwd(),
  mustWork = TRUE
)
source(file.path(repo_root, "R", "run_benchmark.R"))

# ---- preflight --------------------------------------------------------------
# Checked here because both refs are compiled from source: a missing tool should
# stop the run now, not after two installs.

for (pkg in c("bench", "remotes")) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    stop("The '", pkg, "' package is required: install.packages('", pkg, "').",
         call. = FALSE)
  }
}

host <- Sys.info()[["sysname"]]

if ("memory" %in% profiles) {
  if (identical(host, "Darwin")) {
    if (!nzchar(Sys.which("xctrace"))) {
      warning("xctrace was not found; allocation traces will be skipped and only ",
              "RSS numbers recorded.", call. = FALSE)
    }
  } else if (!nzchar(Sys.which("valgrind"))) {
    stop("valgrind is required for memory profiling on ", host, " but was not found.",
         call. = FALSE)
  }
}

if ("cpu" %in% profiles) {
  cpu_profiler <- if (identical(host, "Darwin")) "xctrace" else "perf"
  if (!nzchar(Sys.which(cpu_profiler))) {
    warning(cpu_profiler, " was not found; the run will still produce stage timings, ",
            "but no sampled CPU profile.", call. = FALSE)
  }
}

# ---- run --------------------------------------------------------------------

output_dir <- run_fims_benchmark(
  ref_first = ref_first,
  ref_compare = ref_compare,
  profiles = profiles,
  stage = stage,
  teardown = teardown
)

# ---- reports ----------------------------------------------------------------

reports <- list.files(
  output_dir,
  pattern = "[.]md$|^results_.*[.]tsv$|^manifest[.]tsv$",
  full.names = TRUE
)

if (length(reports)) {
  message("Reports:")
  for (path in reports) message("  ", path)
} else {
  warning("No reports were written; check the *_profile.log files in ", output_dir,
          call. = FALSE)
}
