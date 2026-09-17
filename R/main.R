# The full comparison between two FIMS refs.
#
#   Rscript R/main.R
# or edit the settings below and
#   source("R/main.R")
#
# This runs a matrix of benchmarks rather than one: each row below is a separate
# set of profiled model runs, written to its own directory under outputs/. The
# refs are installed once and reused across every row, so the cost is in the
# measurements, not the builds.
#
# IMPORTANT: use an R session that has never loaded FIMS.

# ---- settings ---------------------------------------------------------------

# Branches the rows with backend "TMB" compare. Every ref is measured against
# the baseline, and ref_compare takes any number of them, so adding a third
# branch is one more entry rather than another pass.
ref_first <- "8bdd020"                          # baseline
ref_compare <- c("update-R-with-XPtr-interface")

# Quadra is a special case and comparisons require a FIMS branch with quadra
# implemented. Setting the two refs bellow to `NULL` will skip the four "quadra-" 
# rows. Both branches must implement Quadra as the backend, a build that does not
# have it will fail the run.
ref_first_quadra <- NULL                        # baseline; NULL skips the rows
ref_compare_quadra <- NULL

# Cycles in each back-to-back loop: the stage built and cleared this many times
# for memory growth, and again for bench::mark() timing. Each cycle is a full
# model build, so at optimize and sdreport this is the slowest part of a row.
bench_iterations <- 20

# Rows with heavy = TRUE are the expensive ones: sdreport at the large model
# under Valgrind is the combination that has run this machine out of memory.
# Set run_heavy <- FALSE to skip them while iterating.
run_heavy <- TRUE

# Set to a vector of row names to run only some of them, or NULL for all.
only <- c("initialize-normal", "initialize-large-clear")

repo_root <- normalizePath(
  if (requireNamespace("here", quietly = TRUE)) here::here() else getwd(),
  mustWork = TRUE
)
source(file.path(repo_root, "R", "run_benchmark.R"))

# ---- the analysis -----------------------------------------------------------
#
# stage is cumulative, so "optimize" includes everything below it and
# "sdreport" includes optimize. The cost of sdreport alone is the difference
# between those two rows -- which is why both are here rather than sdreport
# only.
# 
# size differentiates between the base default model (n = 30) in FIMS and 
# an artifically enlarged population created by repeating the default dataset 
# four times (n = 120)  
#
# teardown rows answer a different question: whether what initialize retained
# is actually released, by clear() or by dropping handles and letting the GC
# run. Those only make sense where there is something retained to release.

#' Model run names: [quadra-]<stage>-<size>[-<teardown>]
#' Labels starting without `quadra-` run TMB by default 
#' A label that does not parse correctly will stop the script
labels <- c(
  "initialize-normal",
  "initialize-normal-clear",
  "initialize-normal-release",
  "optimize-normal",
  "sdreport-normal",
  "quadra-optimize-normal",
  "quadra-sdreport-normal",
  "initialize-large",
  "initialize-large-clear",
  "initialize-large-release",
  "optimize-large",
  "sdreport-large",
  "quadra-optimize-large",
  "quadra-sdreport-large"
)

parse_label <- function(label) {
  word <- strsplit(label, "-", fixed = TRUE)[[1]]
  backend <- if (identical(word[[1]], "quadra")) "quadra" else "TMB"
  if (identical(backend, "quadra")) word <- word[-1]
  stage <- word[[1]]
  size <- if (length(word) > 1L) word[[2]] else ""
  teardown <- if (length(word) > 2L) word[[3]] else "none"
  wrong <- c(
    if (length(word) > 3L) "too many parts",
    if (!stage %in% c("initialize", "tape", "evaluate", "optimize",
                      "sdreport", "helper")) paste0("unknown stage '", stage, "'"),
    if (!size %in% c("normal", "large")) paste0("unknown size '", size, "'"),
    if (!teardown %in% c("none", "clear", "release")) paste0("unknown teardown '", teardown, "'"),
    if (identical(backend, "quadra") && !stage %in% c("optimize", "sdreport"))
      "quadra only means something from the optimize rung up"
  )
  if (length(wrong)) {
    stop("Cannot read the run '", label, "': ", paste(wrong, collapse = "; "),
         ". Expected [quadra-]<stage>-<size>[-<teardown>].", call. = FALSE)
  }
  c(stage = stage, size = size, teardown = teardown, backend = backend)
}

runs <- data.frame(label = labels, stringsAsFactors = FALSE)
runs[, c("stage", "size", "teardown", "backend")] <-
  t(vapply(labels, parse_label, character(4)))

# A teardown row asks whether memory is returned, which no CPU profile answers.
# Leak checks run only at the normal size: memcheck is far slower than Massif,
# and a leak in the teardown code shows up at any size, so the large teardown
# rows measure memory alone. sdreport-normal also gets a leak check, for leaks
# that only appear once the model is fitted.
runs$profiles <- ifelse(runs$teardown == "none", "memory,cpu",
                        ifelse(runs$size == "normal", "memory,leaks", "memory"))
leak_fit <- runs$stage == "sdreport" & runs$size == "normal" & runs$backend == "TMB"
runs$profiles[leak_fit] <- "memory,cpu,leaks"

# Back-to-back runs at the normal size only: many cycles of the large model
# would take far too long, and memory that accumulates does so at any size. The
# loop clears the model every cycle, so the teardown rows add nothing to it.
bench_rows <- runs$size == "normal" & runs$teardown == "none"
runs$profiles[bench_rows] <- paste0(runs$profiles[bench_rows], ",bench")

# The expensive combinations: sdreport at all, and optimizing the large model.
# These are the ones that have run a machine out of memory under Valgrind.
runs$heavy <- runs$stage == "sdreport" |
  (runs$size == "large" & runs$stage == "optimize")

# The quadra rows need their own branches, and without them there is nothing to
# run rather than something to run badly.
if (is.null(ref_first_quadra) || is.null(ref_compare_quadra)) {
  if (any(runs$backend == "quadra")) {
    message("No Quadra branches set, so the quadra rows are skipped. ",
            "Set ref_first_quadra and ref_compare_quadra to include them.")
  }
  runs <- runs[runs$backend != "quadra", , drop = FALSE]
}

# Which branches each row compares. Held as a list column so one row can carry
# several compare refs.
runs$ref_first <- ref_first
runs$ref_compare <- list(ref_compare)
quadra_rows <- runs$backend == "quadra"
if (any(quadra_rows)) {
  runs$ref_first[quadra_rows] <- ref_first_quadra
  runs$ref_compare[quadra_rows] <- list(ref_compare_quadra)
}

# A teardown run means nothing on its own: what clear() or release gave back is
# its difference from the same stage and size torn down by nothing. So choosing
# one brings in that partner.
if (!is.null(only)) {
  chosen <- runs$teardown != "none" & runs$label %in% only
  partners <- setdiff(sub("-(clear|release)$", "", runs$label[chosen]), only)
  partners <- intersect(partners, runs$label)
  if (length(partners)) {
    message("Also running ", paste(partners, collapse = ", "),
            ": teardown runs are compared with the same stage and size without teardown.")
  }
  runs <- runs[runs$label %in% c(only, partners), , drop = FALSE]
}
if (!isTRUE(run_heavy)) runs <- runs[!runs$heavy, , drop = FALSE]
if (!nrow(runs)) stop("No runs selected.", call. = FALSE)

# ---- preflight --------------------------------------------------------------
# Checked once, before anything is compiled.

for (pkg in c("bench", "remotes")) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    stop("The '", pkg, "' package is required: install.packages('", pkg, "').",
         call. = FALSE)
  }
}

host <- Sys.info()[["sysname"]]

# The profilers are run once, not just looked for on PATH: Valgrind execs a
# separate tool binary, and perf will exit 0 having recorded nothing when the
# kernel has no PMU. Both happen on WSL2.

if (any(grepl("memory", runs$profiles))) {
  if (identical(host, "Darwin")) {
    if (!nzchar(Sys.which("xctrace"))) {
      warning("xctrace was not found; allocation traces will be skipped.", call. = FALSE)
    }
  } else {
    massif <- test_valgrind_works()
    if (!isTRUE(massif)) stop("Memory profiling is not usable here: ", massif, call. = FALSE)
    message("Valgrind can run Massif here.")
  }
}

if (any(grepl("cpu", runs$profiles))) {
  if (identical(host, "Darwin")) {
    if (!nzchar(Sys.which("xctrace"))) {
      stop("xctrace was not found, so no CPU profile can be recorded. Install ",
           "Xcode, or remove cpu from the runs.", call. = FALSE)
    }
  } else {
    event <- test_perf_works()
    if (identical(event, "")) {
      message("perf can record with the default event.")
    } else if (identical(event, "cpu-clock")) {
      Sys.setenv(PERF_EVENT = event)
      message("perf: no hardware PMU here, recording with -e ", event, ".")
    } else {
      # Fail fast: a profiler that cannot record here fails every run the same
      # way, and learning that after the whole analysis wastes all of it.
      stop("CPU profiling is not usable here: ", event, call. = FALSE)
    }
  }
}

if (any(grepl("leaks", runs$profiles))) {
  detector <- if (identical(host, "Darwin")) "leaks" else "valgrind"
  if (!nzchar(Sys.which(detector))) {
    # Fail fast: without the detector every leak check fails the same way.
    stop(detector, " is required for leak checks on ", host, ". ", FIX_PROFILERS,
         call. = FALSE)
  }
}

# ---- run --------------------------------------------------------------------
# One row failing does not stop the analysis: a stage that runs out of memory
# should not discard the rows that already succeeded. Failures are collected and
# reported at the end.

results <- data.frame(
  label = runs$label, status = NA_character_, output_dir = NA_character_,
  minutes = NA_real_, stringsAsFactors = FALSE
)

for (index in seq_len(nrow(runs))) {
  row <- runs[index, ]
  message("\n=== [", index, "/", nrow(runs), "] ", row$label,
          " | ", row$ref_first, " vs ", paste(row$ref_compare[[1]], collapse = ", "),
          " | stage=", row$stage, " size=", row$size,
          " backend=", row$backend, " teardown=", row$teardown,
          " profiles=", row$profiles, " ===")

  started <- Sys.time()
  outcome <- tryCatch(
    run_fims_benchmark(
      ref_first = row$ref_first,
      ref_compare = row$ref_compare[[1]],
      profiles = strsplit(row$profiles, ",")[[1]],
      stage = row$stage,
      size = row$size,
      teardown = row$teardown,
      backend = row$backend,
      bench_iterations = bench_iterations,
      label = row$label
    ),
    error = function(e) structure(conditionMessage(e), class = "benchmark_failure")
  )

  results$minutes[index] <- round(
    as.numeric(difftime(Sys.time(), started, units = "mins")), 1)

  if (inherits(outcome, "benchmark_failure")) {
    results$status[index] <- "failed"
    message("!!! ", row$label, " failed: ", outcome)
  } else {
    results$status[index] <- "ok"
    results$output_dir[index] <- outcome
  }
}

# ---- the report --------------------------------------------------------------
# One document for the whole analysis, built from the results.tsv each run
# wrote. Sections appear only where the runs produced the measurement, so an
# analysis of "initialize" alone reports memory and says nothing about a fit.

index_file <- file.path(repo_root, "outputs",
                        paste0(format(Sys.time(), "%Y%m%d"), "_analysis_index.tsv"))
utils::write.table(results, index_file, sep = "\t", row.names = FALSE, quote = FALSE)

report_file <- file.path(repo_root, "outputs",
                         paste0(format(Sys.time(), "%Y%m%d"), "_report.md"))
completed <- results$output_dir[results$status == "ok"]
if (length(completed)) {
  system2("Rscript", c(shQuote(file.path(repo_root, "R", "report.R")),
                       shQuote(report_file), shQuote(completed)))
}

message("\n=== analysis complete ===")
print(results[, c("label", "status", "minutes")])
message("Index: ", index_file)

failed <- results$label[results$status == "failed"]
if (length(failed)) {
  message("Failed rows: ", paste(failed, collapse = ", "),
          " -- see run.log in each run directory.")
}
