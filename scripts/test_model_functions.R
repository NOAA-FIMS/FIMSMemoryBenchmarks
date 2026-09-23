# setup_fims_model() and the two functions in R/run_model_for_profilers.R, run
# against a stub FIMS (scripts/stub_fims), so no real build is needed. The stub
# supports the initialize rung only: the rungs above it need TMB's compiled
# tape, which a real benchmark run exercises.
#
#   Rscript scripts/test_model_functions.R

arguments <- commandArgs(FALSE)
this_file <- sub("^--file=", "", arguments[grep("^--file=", arguments)])
root <- normalizePath(file.path(dirname(this_file), ".."))

# The stub, installed into a library of its own for this run only.
lib <- file.path(tempdir(), "stub_lib")
dir.create(lib)
status <- system2(file.path(R.home("bin"), "R"),
                  c("CMD", "INSTALL", "--no-multiarch", "-l", shQuote(lib),
                    shQuote(file.path(root, "scripts", "stub_fims"))),
                  stdout = FALSE, stderr = FALSE)
stopifnot(identical(as.integer(status), 0L))
.libPaths(c(lib, .libPaths()))

# A repository root whose setup_FIMS.R is the real one with only the inputs
# faked, since building the real inputs needs FIMS's data sets.
repo <- file.path(tempdir(), "repo")
dir.create(file.path(repo, "R"), recursive = TRUE)
dir.create(file.path(repo, "scripts"))
invisible(file.copy(file.path(root, "R", "setup_FIMS.R"), file.path(repo, "R")))
cat("\nsetup_fims_inputs <- function(size = 'normal') {\n",
    "  list(parameters = list(), data = list(), size = size)\n}\n",
    file = file.path(repo, "R", "setup_FIMS.R"), append = TRUE)
invisible(file.copy(file.path(root, "scripts", "heap_in_use.c"), file.path(repo, "scripts")))

source(file.path(root, "R", "run_model_for_profilers.R"))
source(file.path(repo, "R", "setup_FIMS.R"))
suppressMessages(library(FIMS))
input <- setup_fims_inputs()

# Parameter counts are taken before teardown, so clear() does not zero them.
result <- setup_fims_model(input, stage = "initialize", teardown = "clear", record = TRUE)
stopifnot(identical(result$result$n_fixed, 3L), identical(result$result$n_random, 2L),
          identical(result$result$backend, "TMB"),
          all(c("initialize", "teardown") %in% names(result$phases)),
          length(FIMS::get_fixed()) == 0L)

# Without recording, the profiled runs keep nothing extra.
result <- setup_fims_model(input, stage = "initialize", record = FALSE)
stopifnot(is.null(result$result$initial_parameters), is.null(result$result$n_fixed))

# The baseline mode stops after the inputs and writes nothing.
values <- tempfile(fileext = ".rds")
result <- run_model_for_cpp_profiler(stage_mode = "inputs", values_out = values,
                                     repo_root = repo)
stopifnot(is.null(result), !file.exists(values))

# The reference run saves what it computed, and marks a finished run.
marker <- tempfile()
result <- suppressMessages(run_model_for_cpp_profiler(
  stage = "initialize", size = "normal", teardown = "clear",
  values_out = values, leak_marker = marker, repo_root = repo))
stopifnot(inherits(result, "fims_stage_result"), file.exists(values), file.exists(marker))
saved <- readRDS(values)
stopifnot(identical(saved$stage, "initialize"), identical(saved$model_size, "normal"),
          identical(saved$n_fixed, 3L), identical(length(unlist(saved$initial_parameters)), 5L))
if (file.exists("/proc/self/status")) {
  stopifnot(is.numeric(saved$maximum_rss), saved$maximum_rss > 0)
}

# Back-to-back runs: a build that keeps 1 MB every time is reported as growing
# by about 1 MB a cycle, and one that keeps nothing as flat. Linux only, since
# the memory reading is glibc's.
if (identical(Sys.info()[["sysname"]], "Linux")) {
  growth <- function(leak) {
    Sys.setenv(STUB_FIMS_LEAK = leak)
    on.exit(Sys.unsetenv("STUB_FIMS_LEAK"))
    rows <- suppressMessages(run_model_for_R_profiler(
      stage = "initialize", teardown = "clear", iterations = 6, out = "",
      repo_root = repo))
    stopifnot(all(rows$source == "lifecycle"))
    as.numeric(rows$value[rows$metric == "heap_growth_per_cycle"])
  }
  leaky <- growth("1")
  clean <- growth("0")
  stopifnot(abs(leaky - 2^20) < 0.05 * 2^20, abs(clean) < 64 * 1024)
}

cat("Model function checks passed\n")
