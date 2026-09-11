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

ref_first <- "8bdd020"
ref_compare <- "update-R-with-XPtr-interface"

# Rows with heavy = TRUE are the expensive ones: sdreport at the large model
# under Valgrind is the combination that has run this machine out of memory.
# Set run_heavy <- FALSE to skip them while iterating.
run_heavy <- TRUE

# Set to a vector of row names to run only some of them, or NULL for all.
only <- NULL

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
# teardown rows answer a different question: whether what initialize retained
# is actually released, by clear() or by dropping handles and letting the GC
# run. Those only make sense where there is something retained to release.

runs <- data.frame(
  # Validation runs first for each size: its result is cached and reused by the
  # rows that follow, which is what lets them compose final_report.md without
  # re-fitting the model.
  label      = c("validation-normal",
                 "initialize-normal",
                 "optimize-normal",
                 "sdreport-normal",
                 "validation-large",
                 "initialize-large",
                 "initialize-large-clear",
                 "initialize-large-release",
                 "optimize-large",
                 "sdreport-large"),
  # The two validation rows use stage "validation": that profile always runs the
  # validation fit, so any other value here would be ignored but still reported.
  stage      = c("validation", "initialize", "optimize", "sdreport",
                 "validation", "initialize", "initialize", "initialize",
                 "optimize", "sdreport"),
  size       = c("normal", "normal", "normal", "normal",
                 "large", "large", "large", "large",
                 "large", "large"),
  teardown   = c("none", "none", "none", "none",
                 "none", "none", "clear", "release",
                 "none", "none"),
  profiles   = c("validation", "memory,cpu", "memory,cpu", "memory,cpu",
                 "validation", "memory,cpu", "memory", "memory",
                 "memory,cpu", "memory,cpu"),
  heavy      = c(FALSE, FALSE, FALSE, TRUE,
                 TRUE, FALSE, FALSE, FALSE,
                 TRUE, TRUE),
  stringsAsFactors = FALSE
)

if (!is.null(only)) runs <- runs[runs$label %in% only, , drop = FALSE]
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

if (any(grepl("memory", runs$profiles))) {
  if (identical(host, "Darwin")) {
    if (!nzchar(Sys.which("xctrace"))) {
      warning("xctrace was not found; allocation traces will be skipped.", call. = FALSE)
    }
  } else if (!nzchar(Sys.which("valgrind"))) {
    stop("valgrind is required for memory profiling on ", host, ".", call. = FALSE)
  }
}

if (any(grepl("cpu", runs$profiles))) {
  cpu_profiler <- if (identical(host, "Darwin")) "xctrace" else "perf"
  if (!nzchar(Sys.which(cpu_profiler))) {
    warning(cpu_profiler, " was not found; runs will still produce memory ",
            "numbers, but no sampled CPU profile.", call. = FALSE)
  }
}

if (any(grepl("leaks", runs$profiles)) && !identical(host, "Darwin") &&
    !nzchar(Sys.which("valgrind"))) {
  warning("valgrind is required for leak checks on ", host, ".", call. = FALSE)
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
          " | stage=", row$stage, " size=", row$size,
          " teardown=", row$teardown, " profiles=", row$profiles, " ===")

  started <- Sys.time()
  outcome <- tryCatch(
    run_fims_benchmark(
      ref_first = ref_first,
      ref_compare = ref_compare,
      profiles = strsplit(row$profiles, ",")[[1]],
      stage = row$stage,
      size = row$size,
      teardown = row$teardown,
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

# ---- summary ----------------------------------------------------------------

index_file <- file.path(repo_root, "outputs",
                        paste0(format(Sys.time(), "%Y%m%d"), "_analysis_index.tsv"))
utils::write.table(results, index_file, sep = "\t", row.names = FALSE, quote = FALSE)

message("\n=== analysis complete ===")
print(results[, c("label", "status", "minutes")])
message("Index: ", index_file)

failed <- results$label[results$status == "failed"]
if (length(failed)) {
  message("Failed rows: ", paste(failed, collapse = ", "),
          " -- see run.log in each run directory.")
}
