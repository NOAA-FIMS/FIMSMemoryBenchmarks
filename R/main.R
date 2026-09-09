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
#' @param model_size Benchmark scenario: `"large"` uses 120 years and
#'   `"medium"` retains the original 30-year model.
#'
#' @return Invisibly returns the new output directory path.
#' @examples
#' \dontrun{
#' source("R/main.R")
#' compare_fims_branches("main", "remove-direct-rcpp")
#' }
compare_fims_branches <- function(
    ref_first = "main",
    ref_compare = "remove-direct-rcpp-main",
    macos_instruments = TRUE,
    instruments_attach_delay = 6,
    instruments_time_limit = "30m",
    model_size = c("large", "medium")) {
  compare_fims_refs(
    c(ref_first, ref_compare), macos_instruments, instruments_attach_delay,
    instruments_time_limit, model_size
  )
}

#' Compare a vector of FIMS refs, using the first as the baseline
#' @param refs Character vector of branches, tags, or commits. Duplicates run once.
#' @return Invisibly returns the new output directory path.
compare_fims_refs <- function(
    refs,
    macos_instruments = TRUE,
    instruments_attach_delay = 6,
    instruments_time_limit = "30m",
    model_size = c("large", "medium")) {
  model_size <- match.arg(model_size)
  if (!is.character(refs) || !length(refs) || anyNA(refs) ||
      any(!nzchar(refs)) || any(grepl("[[:space:][:cntrl:]]", refs))) {
    stop("`refs` must be a non-empty character vector of ref names without whitespace.", call. = FALSE)
  }
  refs <- unique(refs)
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
    paste0("MACOS_INSTRUMENTS=", as.integer(isTRUE(macos_instruments))),
    paste0("FIMS_INSTRUMENTS_ATTACH_DELAY=", instruments_attach_delay),
    paste0("INSTRUMENTS_TIME_LIMIT=", shQuote(instruments_time_limit)),
    paste0("MODEL_SIZE=", shQuote(model_size))
  )

  message("Comparing FIMS refs: ", paste(refs, collapse = ", "), " (first is baseline)...")
  status <- system2("bash", c(shQuote(runner), shQuote(refs)), env = env)
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
