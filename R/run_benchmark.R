# Compare two FIMS refs with the C++ profilers.
#
# This file does three things, in order: install each ref, profile each ref, and
# report. Profilers are run by scripts/memory.sh and scripts/performance.sh, one
# measurement per call; everything else happens here.
#
# Timing is deliberately absent. Wall-clock numbers for a stage belong in R,
# where bench::mark() can run both without a profiler distorting them.
#
# IMPORTANT: run this in an R session that has never loaded FIMS. Installing a
# different build over a mapped DLL is unreliable.

path_safe <- function(value) gsub("[^A-Za-z0-9._-]", "_", value)

# The commit a ref points at, so a cached build can be checked against it. A
# bare SHA is already immutable; a branch or tag has to be asked of the remote.
# NA means "could not tell", which forces a reinstall rather than risking a
# stale build.
resolve_ref_sha <- function(ref, repo = "https://github.com/NOAA-FIMS/FIMS") {
  if (grepl("^[0-9a-f]{7,40}$", ref)) return(ref)
  out <- suppressWarnings(
    system2("git", c("ls-remote", shQuote(repo), shQuote(ref)), stdout = TRUE, stderr = FALSE))
  if (!length(out) || !nzchar(out[[1]])) return(NA_character_)
  sub("\\s.*$", "", out[[1]])
}

# system2(stdout = file) truncates, so each subprocess would erase the previous
# one's output. Capture and append instead: the log is the only record of why a
# profiler or an install failed.
run_logged <- function(command, args, env = character(), log) {
  output <- suppressWarnings(system2(command, args, env = env,
                                     stdout = TRUE, stderr = TRUE))
  status <- attr(output, "status")
  cat(paste0("\n$ ", command, " ", paste(args, collapse = " "), "\n"),
      paste(output, collapse = "\n"), "\n", file = log, append = TRUE)
  list(status = if (is.null(status)) 0L else as.integer(status), output = output)
}


#' Compare two FIMS refs on one stage of the interface ladder
#'
#' Installs each ref into its own library, then profiles one model run per ref.
#' The fixture is built inside the profiled process, but recording starts after
#' it, so what is recorded is the stage.
#'
#' @param ref_first,ref_compare Branches, tags, or commits to compare.
#' @param profiles "memory" (Valgrind or Instruments allocations), "cpu"
#'   (perf or the Instruments time profiler), or both.
#' @param stage Rung of the ladder, or "helper" for the end-to-end fit. The
#'   ladder is cumulative, so "sdreport" runs everything below it.
#' @param teardown "none" leaves the interface objects alive, so the heap at
#'   exit is what the run retained; "clear" and "release" test whether that
#'   memory is returned.
#' @param mem_baseline Also profile a fixture-only run, so the report can
#'   subtract everything that is not the stage.
#' @param n_eval fn/gr evaluations at stage "evaluate".
#' @param overwrite Replace an earlier run of the same comparison from the same
#'   day. FALSE keeps it and adds a numbered suffix.
#' @param reinstall Rebuild FIMS even when the cached build is already at the
#'   commit the ref points at. Builds are cached in `outputs/.lib-cache` and
#'   reused, since compiling FIMS from source is the slowest part of a run.
#' @param macos_instruments Capture Instruments traces on macOS.
#' @param instruments_attach_delay Seconds the workload waits, after loading the
#'   fixture, for a profiler to attach. Raise it on a slow host.
#' @param instruments_time_limit Maximum Instruments recording duration.
#' @return Invisibly, the path to this run's output directory.
run_fims_benchmark <- function(ref_first = "main",
                               ref_compare = "xptr-refactor",
                               profiles = c("memory", "cpu"),
                               stage = c("initialize", "assemble", "tape",
                                         "evaluate", "optimize", "sdreport",
                                         "helper"),
                               teardown = c("none", "clear", "release"),
                               mem_baseline = TRUE,
                               n_eval = 1L,
                               overwrite = TRUE,
                               reinstall = FALSE,
                               macos_instruments = TRUE,
                               instruments_attach_delay = 6,
                               instruments_time_limit = "30m") {

  if ("FIMS" %in% loadedNamespaces()) {
    stop("Start a fresh R session: FIMS is already loaded, and installing a ",
         "different build over a mapped DLL is unreliable.", call. = FALSE)
  }

  profiles <- match.arg(profiles, c("memory", "cpu"), several.ok = TRUE)
  stage <- match.arg(stage)
  teardown <- match.arg(teardown)

  refs <- unique(c(ref_first, ref_compare))
  if (anyNA(refs) || !all(nzchar(refs))) {
    stop("Both refs must be non-empty branch, tag, or commit names.", call. = FALSE)
  }
  if (length(refs) == 1L) {
    warning("Both refs are '", ref_first, "'; measuring it once.", call. = FALSE)
  }

  repo_root <- normalizePath(
    if (requireNamespace("here", quietly = TRUE)) here::here() else getwd(),
    mustWork = TRUE
  )
  host <- Sys.info()[["sysname"]]

  # ---- run directory ------------------------------------------------------
  # Local date, not UTC: a run started on the evening of the 9th should be
  # filed under the 9th, not tomorrow. manifest.tsv keeps the full timestamp
  # with its offset if a run ever has to be placed exactly.
  run_date <- format(Sys.time(), "%Y%m%d")
  output_dir <- file.path(repo_root, "outputs",
                          paste0(run_date, "_", path_safe(ref_first),
                                 "_vs_", path_safe(ref_compare)))
  if (dir.exists(output_dir) && isTRUE(overwrite)) {
    message("Replacing the earlier run in ", basename(output_dir))
    unlink(output_dir, recursive = TRUE)
  }
  suffix <- 1L
  while (dir.exists(output_dir)) {
    suffix <- suffix + 1L
    output_dir <- paste0(sub("_[0-9]+$", "", output_dir), "_", suffix)
  }
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  run_id <- basename(output_dir)
  log_file <- file.path(output_dir, "run.log")

  message(sprintf("Run %s: '%s' vs '%s' | stage=%s | teardown=%s | profiles=%s",
                  run_id, ref_first, ref_compare, stage, teardown,
                  paste(profiles, collapse = ",")))

  # ---- install each ref into its own library ------------------------------
  build_types <- c(if ("memory" %in% profiles) "debug",
                   if ("cpu" %in% profiles) "profile")
  builds <- list()

  for (build_type in build_types) {
    # Checked in under scripts/, not generated: the flags do not depend on what
    # is being compared. A copy goes into the run directory so a set of results
    # still records the flags that produced it.
    makevars <- file.path(repo_root, "scripts", paste0("Makevars.", build_type))
    if (!file.exists(makevars)) {
      stop("Missing ", makevars, call. = FALSE)
    }
    file.copy(makevars, file.path(output_dir, basename(makevars)), overwrite = TRUE)

    for (ref in refs) {
      # Libraries live outside the run directory and are reused: a source build
      # of FIMS is the slowest part of a run, and rebuilding an unchanged commit
      # gains nothing.
      lib <- file.path(repo_root, "outputs", ".lib-cache", build_type, path_safe(ref))
      dir.create(lib, recursive = TRUE, showWarnings = FALSE)
      sha_file <- file.path(lib, ".installed-sha")
      wanted_sha <- resolve_ref_sha(ref)
      cached_sha <- if (file.exists(sha_file)) readLines(sha_file, warn = FALSE)[[1]] else NA_character_
      have_build <- dir.exists(file.path(lib, "FIMS"))
      # R_LIBS prepends; R_LIBS_USER would *replace* the user library and hide
      # every package already installed there, so remotes would rebuild the
      # whole dependency tree for each ref.
      env <- c(paste0("R_LIBS=", shQuote(lib)),
               paste0("R_MAKEVARS_USER=", shQuote(makevars)),
               "R_REMOTES_UPGRADE=never",
               paste0("REPO_ROOT=", shQuote(repo_root)),
               paste0("FIMS_REF=", shQuote(ref)))

      reuse <- have_build && !isTRUE(reinstall) &&
        !is.na(cached_sha) && !is.na(wanted_sha) && identical(cached_sha, wanted_sha)

      if (reuse) {
        message("  reusing ", ref, " (", build_type, ") at ", substr(cached_sha, 1, 7))
      } else {
      message("  installing ", ref, " (", build_type, ")")
      code <- run_logged("Rscript",
                         c("-e", shQuote(paste0("source(file.path(Sys.getenv('REPO_ROOT'), 'R', 'setup_FIMS.R')); ",
                                                "install_fims_debug(Sys.getenv('FIMS_REF'))"))),
                         env = env, log = log_file)$status
      if (code != 0L) {
        stop("Installing '", ref, "' (", build_type, ") failed; see ", log_file, call. = FALSE)
      }
      if (!is.na(wanted_sha)) writeLines(wanted_sha, sha_file) else unlink(sha_file)
      }

      # Report where FIMS was found as well as its version: with the user
      # library still visible, a failed install would otherwise fall back to a
      # previously installed FIMS without saying so.
      found <- tail(system2("Rscript",
                            c("-e", shQuote(paste0("cat(as.character(packageVersion('FIMS')), ",
                                                   "dirname(system.file(package = 'FIMS')), sep = '|')"))),
                            env = env, stdout = TRUE), 1L)
      parts <- strsplit(found, "|", fixed = TRUE)[[1]]
      version <- parts[[1]]
      if (length(parts) < 2 || !identical(normalizePath(parts[[2]], mustWork = FALSE),
                                          normalizePath(lib, mustWork = FALSE))) {
        stop("FIMS for '", ref, "' (", build_type, ") was loaded from ",
             if (length(parts) > 1) parts[[2]] else "an unknown library",
             " rather than ", lib, "; the install did not land where it should.",
             call. = FALSE)
      }

      builds[[build_type]][[ref]] <- list(lib = lib, version = version,
                                          sha = wanted_sha)
    }
  }

  versions <- vapply(refs, function(ref) builds[[build_types[[1]]]][[ref]]$version,
                     character(1))

  # Two branches often share a DESCRIPTION version, so record the commit each
  # ref resolved to. This is the file to check when a result looks wrong.
  utils::write.table(
    data.frame(
      ref = refs,
      version = versions,
      commit = vapply(refs, function(ref) {
        sha <- builds[[build_types[[1]]]][[ref]]$sha
        if (is.null(sha) || is.na(sha)) "unknown" else sha
      }, character(1)),
      library = vapply(refs, function(ref) builds[[build_types[[1]]]][[ref]]$lib,
                       character(1)),
      stringsAsFactors = FALSE),
    file.path(output_dir, "refs.tsv"), sep = "\t", row.names = FALSE, quote = FALSE)

  # ---- profile ------------------------------------------------------------
  # scripts/collect.py turns this list of artifacts into results.tsv.
  inputs <- list()
  signatures <- list()

  add_input <- function(kind, ref, stage_label, round, tag, path) {
    inputs[[length(inputs) + 1L]] <<- data.frame(
      kind = kind, ref = ref, version = versions[[ref]], stage = stage_label,
      round = round, tag = tag, path = path, stringsAsFactors = FALSE)
  }

  profile_run <- function(script, args, capture = FALSE) {
    args <- c(shQuote(file.path(repo_root, "scripts", script)), args,
              "--repo-root", shQuote(repo_root))
    result <- run_logged("bash", args, log = log_file)
    if (capture) {
      # The wrapper prints one status word, but its diagnostics land in the same
      # captured stream, so match the word rather than trusting the last line.
      states <- grep("^(captured|captured-export-failed|failed|unavailable|disabled)$",
                     result$output, value = TRUE)
      if (length(states)) tail(states, 1L) else "failed"
    } else {
      result$status
    }
  }

  status <- integer()

  if ("memory" %in% profiles) {
    tool <- if (identical(host, "Darwin")) "time" else "massif"
    kind <- if (identical(host, "Darwin")) "time" else "massif"
    memory_status <- 0L

    for (ref in refs) {
      build <- builds[["debug"]][[ref]]

      if (isTRUE(mem_baseline)) {
        out <- file.path(output_dir, paste0("baseline_", path_safe(ref), ".out"))
        message("  memory baseline: ", ref)
        code <- profile_run("memory.sh",
                            c("--tool", tool, "--lib", shQuote(build$lib),
                              "--stage", stage, "--mode", "fixture",
                              "--teardown", teardown, "--out", shQuote(out)))
        # Fail on the first failure rather than repeating it for every ref and
        # profiler: when the model itself is broken, every later measurement
        # fails the same way and each one is slow.
        if (code != 0L) {
          stop("Memory baseline for '", ref, "' exited with status ", code,
               ". See ", log_file, call. = FALSE)
        }
        add_input(kind, ref, "fixture", 1L, "", out)
      }

      if (identical(host, "Darwin") && isTRUE(macos_instruments)) {
        trace <- file.path(output_dir, paste0("alloc_", path_safe(ref), ".trace"))
        message("  Instruments allocations: ", ref)
        profile_run("memory.sh",
                    c("--tool", "instruments", "--lib", shQuote(build$lib),
                      "--stage", stage, "--teardown", teardown,
                      "--out", shQuote(trace),
                      "--attach-delay", instruments_attach_delay,
                      "--time-limit", instruments_time_limit))
        add_input("instruments-alloc", ref, stage, 1L, "", trace)
      }
    }

    # One profiled model run per ref. Repetition belongs in the R profiler,
    # where bench::mark() can iterate without a profiler distorting the result.
    for (ref in refs) {
      build <- builds[["debug"]][[ref]]
      out <- file.path(output_dir, paste0("massif_", path_safe(ref), ".out"))
      signature <- file.path(output_dir, paste0("signature_", path_safe(ref), ".tsv"))
      signatures[[ref]] <- signature

      message("  memory profile: ", ref)
      code <- profile_run("memory.sh",
                          c("--tool", tool, "--lib", shQuote(build$lib),
                            "--stage", stage, "--mode", "stage",
                            "--teardown", teardown, "--out", shQuote(out),
                            "--signature", shQuote(signature)))
      if (code != 0L) {
        stop("Memory profile for '", ref, "' exited with status ", code,
             ". See ", log_file, call. = FALSE)
      }
      add_input(kind, ref, stage, 1L, "", out)
    }
    status[["memory"]] <- memory_status
  }

  if ("cpu" %in% profiles) {
    tool <- if (identical(host, "Darwin")) "instruments" else "perf"
    cpu_states <- character()
    for (ref in refs) {
      build <- builds[["profile"]][[ref]]
      out <- file.path(output_dir, paste0("cpu_", path_safe(ref),
                                          if (tool == "perf") ".data" else ".trace"))
      report <- file.path(output_dir, paste0("cpu_", path_safe(ref), ".txt"))
      message("  CPU profile: ", ref)
      state <- profile_run("performance.sh",
                           c("--tool", tool, "--lib", shQuote(build$lib),
                             "--stage", stage, "--teardown", teardown,
                             "--out", shQuote(out), "--report", shQuote(report),
                                    "--n-eval", n_eval,
                             "--attach-delay", instruments_attach_delay,
                             "--time-limit", instruments_time_limit),
                           capture = TRUE)
      cpu_states[[ref]] <- state
      if (identical(state, "failed")) {
        stop("CPU profile for '", ref, "' failed. See ", log_file, call. = FALSE)
      }
      add_input("cpu-status", ref, stage, 1L, state, report)
      if (grepl("^captured", state)) {
        add_input(if (tool == "perf") "perf" else "instruments-cpu",
                  ref, stage, 1L, "", report)
      }
    }
    status[["cpu"]] <- if (any(cpu_states == "failed")) 1L else 0L
  }

  # ---- collect and report -------------------------------------------------
  inputs_file <- file.path(output_dir, "inputs.tsv")
  results_file <- file.path(output_dir, "results.tsv")
  report_file <- file.path(output_dir, "report.md")

  utils::write.table(do.call(rbind, inputs), inputs_file, sep = "\t",
                     row.names = FALSE, quote = FALSE)
  collected <- run_logged("python3",
                          c(shQuote(file.path(repo_root, "scripts", "collect.py")),
                            "--inputs", shQuote(inputs_file),
                            "--teardown", teardown,
                            "--output", shQuote(results_file)),
                          log = log_file)$status

  if (collected == 0L && file.exists(results_file)) {
    signature_args <- unlist(lapply(names(signatures), function(ref) {
      if (file.exists(signatures[[ref]])) c("--signature", shQuote(ref), shQuote(signatures[[ref]]))
    }))
    run_logged("python3",
            c(shQuote(file.path(repo_root, "scripts", "report.py")),
              "--results", shQuote(results_file),
              "--stage", stage, "--teardown", teardown,
              "--platform", host, "--run-id", shQuote(run_id),
              signature_args,
              "--output", shQuote(report_file)),
            log = log_file)
  } else {
    warning("Collecting measurements failed; see ", log_file, call. = FALSE)
    report_file <- NA_character_
  }

  # ---- name the run for what it compared ----------------------------------
  compare_label <- path_safe(ref_compare)
  if (length(refs) == 2L && !identical(versions[[ref_compare]], versions[[ref_first]])) {
    compare_label <- paste0(compare_label, "-", path_safe(versions[[ref_compare]]))
  }
  renamed <- file.path(repo_root, "outputs",
                       paste0(run_date, "_", path_safe(ref_first), "-",
                              path_safe(versions[[ref_first]]), "_vs_", compare_label))
  # The final name carries the version, so an earlier run of the same
  # comparison is replaced here too, not just at the pre-rename path.
  if (dir.exists(renamed) && isTRUE(overwrite) && !identical(renamed, output_dir)) {
    unlink(renamed, recursive = TRUE)
  }
  if (!dir.exists(renamed) && file.rename(output_dir, renamed)) {
    output_dir <- renamed
    run_id <- basename(renamed)
    if (!is.na(report_file)) report_file <- file.path(output_dir, basename(report_file))
    log_file <- file.path(output_dir, basename(log_file))
  }

  manifest <- data.frame(
    run_id = run_id, stage = stage, teardown = teardown,
    ref_first = ref_first, ref_compare = ref_compare,
    profile = names(status), status = unname(status),
    timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    stringsAsFactors = FALSE)
  utils::write.table(manifest, file.path(output_dir, "manifest.tsv"),
                     sep = "\t", row.names = FALSE, quote = FALSE)

  message("Done: ", output_dir)
  if (!is.na(report_file)) message("Report: ", report_file)
  print(manifest[, c("profile", "status")])

  # A profiler that could not run at all (a missing tool, say) does not abort
  # the run, but it must not be reported as a success either.
  failed <- names(status)[status != 0L]
  if (length(failed)) {
    stop("These profiles did not complete: ", paste(failed, collapse = ", "),
         ". See ", log_file, call. = FALSE)
  }

  invisible(output_dir)
}

