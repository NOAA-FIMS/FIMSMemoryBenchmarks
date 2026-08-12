#' Compare memory usage between two FIMS refs
#'
#' Calls `scripts/run_massif.sh`, which selects Valgrind Massif on Linux and
#' Instruments plus `/usr/bin/time -l` on macOS.
#'
#' @param ref_first Baseline branch, tag, or commit.
#' @param ref_compare Branch, tag, or commit compared with `ref_first`.
#' @param macos_instruments Whether to capture an Instruments Allocations trace
#'   on macOS. Ignored on other platforms.
#' @param instruments_attach_delay Seconds R waits before Instruments attaches.
#' @param instruments_time_limit Maximum Instruments recording duration, using
#'   an `xctrace` duration such as `30m` or `1h`.
#'
#' @return Invisibly returns the new output directory path.
#' @examples
#' \dontrun{
#' source("R/main.R")
#' compare_fims_branches("main", "remove-direct-rcpp")
#' }
compare_fims_branches <- function(
    ref_first = "main",
    ref_compare = "remove-direct-rcpp",
    macos_instruments = TRUE,
    instruments_attach_delay = 6,
    instruments_time_limit = "30m") {
  refs <- c(ref_first = ref_first, ref_compare = ref_compare)
  if (anyNA(refs) || any(!nzchar(refs))) {
    stop("Both refs must be non-empty branch, tag, or commit names.", call. = FALSE)
  }
  if (length(macos_instruments) != 1L || is.na(macos_instruments)) {
    stop("`macos_instruments` must be TRUE or FALSE.", call. = FALSE)
  }
  if (!is.numeric(instruments_attach_delay) ||
      length(instruments_attach_delay) != 1L ||
      is.na(instruments_attach_delay) ||
      instruments_attach_delay < 0) {
    stop("`instruments_attach_delay` must be one non-negative number.", call. = FALSE)
  }

  repo_root <- normalizePath(
    if (requireNamespace("here", quietly = TRUE)) here::here() else getwd(),
    mustWork = TRUE
  )
  runner <- file.path(repo_root, "scripts", "run_massif.sh")
  if (!file.exists(runner)) {
    stop("Could not find scripts/run_massif.sh from ", repo_root, call. = FALSE)
  }

  outputs <- file.path(repo_root, "outputs")
  before <- if (dir.exists(outputs)) list.dirs(outputs, recursive = FALSE) else character()
  old_dir <- setwd(repo_root)
  on.exit(setwd(old_dir), add = TRUE)

  env <- c(
    paste0("REF_FIRST=", shQuote(ref_first)),
    paste0("REF_COMPARE=", shQuote(ref_compare)),
    paste0("MACOS_INSTRUMENTS=", as.integer(isTRUE(macos_instruments))),
    paste0("FIMS_INSTRUMENTS_ATTACH_DELAY=", instruments_attach_delay),
    paste0("INSTRUMENTS_TIME_LIMIT=", shQuote(instruments_time_limit))
  )

  message(sprintf("Comparing FIMS '%s' (baseline) with '%s'...", ref_first, ref_compare))
  status <- system2("bash", runner, env = env)
  if (!identical(status, 0L)) {
    stop("Memory benchmark failed with exit status ", status, ".", call. = FALSE)
  }

  after <- list.dirs(outputs, recursive = FALSE)
  new_outputs <- setdiff(after, before)
  output_dir <- if (length(new_outputs)) {
    new_outputs[[which.max(file.info(new_outputs)$mtime)]]
  } else {
    outputs
  }

  message("Benchmark complete: ", output_dir)
  invisible(output_dir)
}
