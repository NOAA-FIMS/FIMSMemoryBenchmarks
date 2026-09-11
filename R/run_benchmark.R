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

`%||%` <- function(x, y) if (is.null(x)) y else x

#' Validate and de-duplicate the refs a run will compare
#'
#' Every ref is compared against the first. Duplicates are dropped rather than
#' measured twice, and refs that differ only in characters that are not
#' filename-safe are rejected: they would write to the same paths and silently
#' overwrite each other.
#'
#' Separate from run_fims_benchmark() so it can be tested without installing
#' anything.
#'
#' @param ref_first Baseline branch, tag, or commit.
#' @param ref_compare One or more refs to compare against it.
#' @return The refs to measure, in order, first one first.
resolve_refs <- function(ref_first, ref_compare = character()) {
  if (!is.character(ref_first) || !is.character(ref_compare)) {
    stop("Refs must be character vectors.", call. = FALSE)
  }
  refs <- c(ref_first, ref_compare)
  if (!length(refs) || anyNA(refs) || !all(nzchar(refs))) {
    stop("Every ref must be a non-empty branch, tag, or commit name.", call. = FALSE)
  }
  if (any(grepl("\\s", refs))) {
    stop("Ref names cannot contain whitespace: ",
         paste(refs[grepl("\\s", refs)], collapse = ", "), call. = FALSE)
  }

  if (anyDuplicated(refs)) {
    warning("Dropping duplicate refs: ",
            paste(unique(refs[duplicated(refs)]), collapse = ", "), call. = FALSE)
    refs <- unique(refs)
  }

  safe_names <- vapply(refs, path_safe, character(1))
  if (anyDuplicated(safe_names)) {
    collisions <- refs[safe_names %in% safe_names[duplicated(safe_names)]]
    stop("These refs collide once made filename-safe: ",
         paste(collisions, collapse = ", "), call. = FALSE)
  }
  if (length(refs) == 1L) {
    warning("Only one distinct ref; measuring it once with nothing to compare.",
            call. = FALSE)
  }
  refs
}


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
#' @param ref_first Baseline branch, tag, or commit: every other ref is
#'   compared against it.
#' @param ref_compare One or more refs to compare with `ref_first`.
#' @param profiles Any of "memory" (Valgrind or Instruments allocations), "cpu"
#'   (perf or the Instruments time profiler), "validation" (the joint objective
#'   fit, saved for the validation report) and "leaks" (memcheck or the macOS
#'   leaks tool). Each is a separate model run.
#' @param stage Rung of the ladder, or "helper" for the end-to-end fit. The
#'   ladder is cumulative, so "sdreport" runs everything below it.
#' @param teardown "none" leaves the interface objects alive, so the heap at
#'   exit is what the run retained; "clear" and "release" test whether that
#'   memory is returned.
#' @param size Fixture size, passed to setup_fims_inputs(): "normal" is
#'   data_big as shipped (30 years), "large" expands it to 120.
#' @param mem_baseline Also profile a fixture-only run, so the report can
#'   subtract everything that is not the stage.
#' @param n_eval fn/gr evaluations at stage "evaluate".
#' @param label Appended to the run directory name. A full analysis runs the
#'   same refs many times, so without a label each run would overwrite the last.
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
                               profiles = c("memory", "cpu", "validation", "leaks"),
                               stage = c("initialize", "assemble", "tape",
                                         "evaluate", "optimize", "sdreport",
                                         "helper", "validation"),
                               teardown = c("none", "clear", "release"),
                               size = c("normal", "large"),
                               mem_baseline = TRUE,
                               n_eval = 1L,
                               label = "",
                               overwrite = TRUE,
                               reinstall = FALSE,
                               macos_instruments = TRUE,
                               instruments_attach_delay = 6,
                               instruments_time_limit = "30m") {

  if ("FIMS" %in% loadedNamespaces()) {
    stop("Start a fresh R session: FIMS is already loaded, and installing a ",
         "different build over a mapped DLL is unreliable.", call. = FALSE)
  }

  profiles <- match.arg(profiles, c("memory", "cpu", "validation", "leaks"),
                        several.ok = TRUE)
  stage <- match.arg(stage)
  teardown <- match.arg(teardown)
  size <- match.arg(size)

  refs <- resolve_refs(ref_first, ref_compare)

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
  label_suffix <- if (nzchar(label)) paste0("_", path_safe(label)) else ""
  compare_names <- paste(vapply(refs[-1], path_safe, character(1)), collapse = "_vs_")
  if (!nzchar(compare_names)) compare_names <- "alone"
  output_dir <- file.path(repo_root, "outputs",
                          paste0(run_date, "_", path_safe(ref_first),
                                 "_vs_", compare_names, label_suffix))
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

  message(sprintf("Run %s: '%s' vs %s | stage=%s | size=%s | teardown=%s | profiles=%s",
                  run_id, ref_first,
                  paste0("'", paste(refs[-1], collapse = "', '"), "'"),
                  stage, size, teardown,
                  paste(profiles, collapse = ",")))

  # ---- install each ref into its own library ------------------------------
  build_types <- unique(c(
    if (any(c("memory", "leaks") %in% profiles)) "debug",
    if (any(c("cpu", "validation") %in% profiles)) "profile"
  ))
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

      build_profile <- file.path(
        output_dir, paste0("build_profile_", build_type, "_", path_safe(ref), ".txt"))

      if (reuse) {
        message("  reusing ", ref, " (", build_type, ") at ", substr(cached_sha, 1, 7))
      } else {
      message("  installing ", ref, " (", build_type, ")")
      # Wrapped in /usr/bin/time so the build itself is a measurement: a
      # refactor that halves run time but doubles compile time is worth seeing.
      install_command <- c("-e", shQuote(paste0(
        "source(file.path(Sys.getenv('REPO_ROOT'), 'R', 'setup_FIMS.R')); ",
        "install_fims(Sys.getenv('FIMS_REF'))")))
      # GNU time is a separate package on Debian (`apt install time`); the
      # shell keyword cannot write a file, so without it the build simply is
      # not measured and the console summary shows build cost as missing.
      if (file.exists("/usr/bin/time")) {
        time_flag <- if (identical(host, "Darwin")) "-l" else "-v"
        code <- run_logged("/usr/bin/time",
                           c(time_flag, "-o", shQuote(build_profile), "Rscript", install_command),
                           env = env, log = log_file)$status
      } else {
        code <- run_logged("Rscript", install_command, env = env, log = log_file)$status
      }
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
      if (!length(found) || !nzchar(found)) {
        stop("Could not read the FIMS version from ", lib,
             ". The install reported success but left nothing installed; see ",
             log_file, call. = FALSE)
      }
      parts <- strsplit(found, "|", fixed = TRUE)[[1]]
      version <- parts[[1]]
      if (length(parts) < 2 || !identical(normalizePath(parts[[2]], mustWork = FALSE),
                                          normalizePath(lib, mustWork = FALSE))) {
        stop("FIMS for '", ref, "' (", build_type, ") was loaded from ",
             if (length(parts) > 1) parts[[2]] else "an unknown library",
             " rather than ", lib, "; the install did not land where it should.",
             call. = FALSE)
      }

      builds[[build_type]][[ref]] <- list(
        lib = lib, version = version, sha = wanted_sha,
        # A reused build was not compiled in this run, so there is no profile.
        build_profile = if (file.exists(build_profile)) build_profile else "")
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
  # inputs.tsv records every artifact produced; scripts/tidy.py turns the
  # reporters' own parses into results.tsv (Phase 5).
  inputs <- list()
  signatures <- list()

  # His summarizers take file paths in fixed argument shapes rather than tidy
  # rows, so the driver accumulates those vectors as the measurements happen.
  summary_args <- character()      # memory: --run REF VERSION <prefix|profile> [status trace]
  baseline_args <- character()     # memory: --baseline REF PREFIX
  cpu_summary_args <- character()  # cpu:    --run REF VERSION STATUS PATH
  console_args <- character()      # console: --run REF PROFILE RUNTIME BUILD LEAKS
  native_profiles <- list()        # macOS /usr/bin/time -l profiles, per ref
  trace_status <- list()           # macOS Instruments status, per ref
  runtime_files <- list()          # validation .runtime_seconds, per ref

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
                              "--stage", stage, "--size", size, "--mode", "fixture",
                              "--teardown", teardown, "--out", shQuote(out)))
        # Fail on the first failure rather than repeating it for every ref and
        # profiler: when the model itself is broken, every later measurement
        # fails the same way and each one is slow.
        if (code != 0L) {
          stop("Memory baseline for '", ref, "' exited with status ", code,
               ". See ", log_file, call. = FALSE)
        }
        add_input(kind, ref, "fixture", 1L, "", out)
        if (identical(tool, "massif")) {
          baseline_args <- c(baseline_args, "--baseline", shQuote(ref), shQuote(out))
        }
      }

      if (identical(host, "Darwin") && isTRUE(macos_instruments)) {
        trace <- file.path(output_dir, paste0("alloc_", path_safe(ref), ".trace"))
        message("  Instruments allocations: ", ref)
        profile_run("memory.sh",
                    c("--tool", "instruments", "--lib", shQuote(build$lib),
                      "--stage", stage, "--size", size, "--teardown", teardown,
                      "--out", shQuote(trace),
                      "--attach-delay", instruments_attach_delay,
                      "--time-limit", instruments_time_limit))
        add_input("instruments-alloc", ref, stage, 1L, "", trace)
        trace_status[[ref]] <- if (file.exists(trace)) "captured" else "failed"
        summary_args <- c(summary_args, "--run", shQuote(ref), shQuote(build$version),
                          shQuote(native_profiles[[ref]] %||% ""),
                          shQuote(trace_status[[ref]]), shQuote(trace))
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
                            "--stage", stage, "--size", size, "--mode", "stage",
                            "--teardown", teardown, "--out", shQuote(out),
                            "--signature", shQuote(signature)))
      if (code != 0L) {
        stop("Memory profile for '", ref, "' exited with status ", code,
             ". See ", log_file, call. = FALSE)
      }
      add_input(kind, ref, stage, 1L, "", out)
      if (identical(tool, "massif")) {
        summary_args <- c(summary_args, "--run", shQuote(ref), shQuote(build$version),
                          shQuote(out))
      } else {
        native_profiles[[ref]] <- out
      }
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
      cpu_summary_args <- c(cpu_summary_args, "--run", shQuote(ref), shQuote(build$version),
                            shQuote(state), shQuote(report))
      if (grepl("^captured", state)) {
        add_input(if (tool == "perf") "perf" else "instruments-cpu",
                  ref, stage, 1L, "", report)
      }
    }
    status[["cpu"]] <- if (any(cpu_states == "failed")) 1L else 0L
  }

  # Validation: the joint objective fit, saved whole because
  # R/summarize_validation.R and the final reports read the structure. Wall time
  # is recorded by scripts/time_command.py, which is what the console summary
  # reports as total validation runtime.
  # A validation result depends on the ref, the build and the model size -- not
  # on which stage is being profiled -- so it is cached and reused. That is what
  # lets every run compose final_report.md without re-fitting the model.
  validation_cache <- file.path(repo_root, "outputs", ".validation-cache")
  dir.create(validation_cache, recursive = TRUE, showWarnings = FALSE)
  cached_validation <- function(ref) {
    build <- builds[[if ("profile" %in% build_types) "profile" else build_types[[1]]]][[ref]]
    sha <- if (is.null(build$sha) || is.na(build$sha)) "unknown" else substr(build$sha, 1, 12)
    file.path(validation_cache,
              paste0(path_safe(ref), "_", sha, "_", size, ".rds"))
  }

  validation_args <- character()
  if ("validation" %in% profiles) {
    for (ref in refs) {
      build <- builds[["profile"]][[ref]]
      out <- file.path(output_dir,
                       paste0("joint_validation_", path_safe(ref), "_", build$version, ".rds"))
      message("  validation: ", ref)
      code <- run_logged(
        "python3",
        c(shQuote(file.path(repo_root, "scripts", "time_command.py")),
          "--output", shQuote(paste0(out, ".runtime_seconds")), "--",
          "Rscript", shQuote(file.path(repo_root, "R", "run_stage.R"))),
        env = c(paste0("R_LIBS=", shQuote(build$lib)),
                paste0("REPO_ROOT=", shQuote(repo_root)),
                paste0("REF_LABEL=", shQuote(ref)),
                "FIMS_STAGE=validation",
                paste0("FIMS_SIZE=", size),
                paste0("TEARDOWN=", shQuote(teardown)),
                paste0("VALIDATION_OUT=", shQuote(out))),
        log = log_file)$status
      if (code != 0L) {
        stop("Validation for '", ref, "' exited with status ", code, ". See ",
             log_file, call. = FALSE)
      }
      validation_args <- c(validation_args, shQuote(ref), shQuote(out))
      runtime_files[[ref]] <- paste0(out, ".runtime_seconds")
      # Keep it for later runs of the same ref, build and size.
      file.copy(out, cached_validation(ref), overwrite = TRUE)
      if (file.exists(runtime_files[[ref]])) {
        file.copy(runtime_files[[ref]],
                  paste0(cached_validation(ref), ".runtime_seconds"), overwrite = TRUE)
      }
      status[["validation"]] <- 0L
    }
  }

  # Leaks: a separate instrumented run of the same fit. Failure here is
  # reported, not fatal -- a missing detector should not discard the profiles.
  leak_args <- character()
  if ("leaks" %in% profiles) {
    leak_status <- 0L
    for (ref in refs) {
      build <- builds[["debug"]][[ref]]
      out <- file.path(output_dir,
                       paste0("leaks_", path_safe(ref), "_", build$version, ".json"))
      message("  leak check: ", ref)
      code <- run_logged(
        "python3",
        c(shQuote(file.path(repo_root, "scripts", "check_leaks.py")),
          "--ref", shQuote(ref), "--output", shQuote(out)),
        env = c(paste0("R_LIBS=", shQuote(build$lib)),
                paste0("REPO_ROOT=", shQuote(repo_root)),
                paste0("FIMS_SIZE=", size)),
        log = log_file)$status
      if (code != 0L) {
        leak_status <- code
        warning("Leak check for '", ref, "' exited with status ", code,
                "; see ", log_file, call. = FALSE, immediate. = TRUE)
      }
      leak_args <- c(leak_args, out)
    }
    status[["leaks"]] <- leak_status
  }

  if (!length(validation_args) && "memory" %in% profiles) {
    for (ref in refs) {
      cached <- cached_validation(ref)
      if (!file.exists(cached)) next
      build <- builds[[build_types[[1]]]][[ref]]
      copy <- file.path(output_dir,
                        paste0("joint_validation_", path_safe(ref), "_", build$version, ".rds"))
      file.copy(cached, copy, overwrite = TRUE)
      runtime_cached <- paste0(cached, ".runtime_seconds")
      if (file.exists(runtime_cached)) {
        file.copy(runtime_cached, paste0(copy, ".runtime_seconds"), overwrite = TRUE)
        runtime_files[[ref]] <- paste0(copy, ".runtime_seconds")
      }
      validation_args <- c(validation_args, shQuote(ref), shQuote(copy))
    }
    if (length(validation_args)) {
      message("  reusing cached validation results for the composed reports")
    }
  }

  # console_summary.py wants one row per ref: the native profile, the validation
  # runtime, the build profile and the leak JSON. Missing pieces are passed as
  # empty strings, which it renders as "-".
  for (ref in refs) {
    build <- builds[[build_types[[1]]]][[ref]]
    leak_file <- ""
    if (length(leak_args)) {
      hit <- grep(paste0("leaks_", path_safe(ref), "_"), leak_args, value = TRUE)
      if (length(hit)) leak_file <- hit[[1]]
    }
    console_args <- c(console_args, "--run", shQuote(ref),
                      shQuote(native_profiles[[ref]] %||% ""),
                      shQuote(runtime_files[[ref]] %||% ""),
                      shQuote(build$build_profile %||% ""),
                      shQuote(leak_file))
  }

  # ---- report ---------------------------------------------------------------
  # The reporting is upstream's: each summarizer parses the artifacts it knows
  # and renders its own Markdown, and final_report.R and management_summary.R
  # compose those into the documents people actually read.

  reports <- character()
  report_path <- function(name) file.path(output_dir, name)

  run_reporter <- function(command, args, produces) {
    result <- run_logged(command, args, log = log_file)
    if (result$status != 0L || !file.exists(produces)) {
      warning("Report ", basename(produces), " was not produced; see ", log_file,
              call. = FALSE, immediate. = TRUE)
      return(invisible(NULL))
    }
    reports <<- c(reports, produces)
    invisible(produces)
  }

  tidy_files <- character()
  tidy_path <- function(name) {
    path <- file.path(output_dir, paste0("tidy_", name, ".tsv"))
    tidy_files <<- c(tidy_files, path)
    shQuote(path)
  }

  cpu_report <- report_path("cpu_profile_report.md")
  if (length(cpu_summary_args)) {
    run_reporter("python3",
                 c(shQuote(file.path(repo_root, "scripts", "summarize_cpu.py")),
                   "--platform", host, cpu_summary_args,
                   "--tidy-out", tidy_path("cpu"),
                   "--output", shQuote(cpu_report)),
                 cpu_report)
  }

  validation_report <- report_path("joint_validation_report.md")
  if (length(validation_args)) {
    run_reporter("Rscript",
                 c(shQuote(file.path(repo_root, "R", "summarize_validation.R")),
                   shQuote(validation_report), "--tidy-out", tidy_path("validation"),
                   validation_args),
                 validation_report)
  }

  memory_report <- report_path(
    if (identical(host, "Darwin")) "macos_memory_report.md" else "valgrind_massif_report.md")
  if (length(summary_args)) {
    summarizer <- if (identical(host, "Darwin")) "summarize_macos.py" else "summarize_massif.py"
    run_reporter("python3",
                 c(shQuote(file.path(repo_root, "scripts", summarizer)),
                   summary_args, baseline_args,
                   "--tidy-out", tidy_path("memory"),
                   "--output", shQuote(memory_report)),
                 memory_report)
  }

  leak_report <- report_path("leak_report.md")
  if (length(leak_args)) {
    run_reporter("python3",
                 c(shQuote(file.path(repo_root, "scripts", "check_leaks.py")),
                   "--report", shQuote(leak_args), "--output", shQuote(leak_report)),
                 leak_report)
  }

  # The composed documents need the validation results, so they are only written
  # when a validation run is part of this benchmark.
  final_report <- report_path("final_report.md")
  management_report <- report_path("management_summary.md")
  if (length(validation_args) && file.exists(memory_report)) {
    run_reporter("Rscript",
                 c(shQuote(file.path(repo_root, "R", "final_report.R")),
                   shQuote(final_report), shQuote(memory_report),
                   shQuote(if (file.exists(cpu_report)) cpu_report else ""),
                   shQuote(validation_report), validation_args),
                 final_report)
    run_reporter("Rscript",
                 c(shQuote(file.path(repo_root, "R", "management_summary.R")),
                   shQuote(management_report), shQuote(memory_report),
                   shQuote(validation_report), validation_args),
                 management_report)
  }

  results_file <- file.path(output_dir, "results.tsv")
  existing <- tidy_files[file.exists(tidy_files)]
  if (length(existing)) {
    run_logged("python3",
               c(shQuote(file.path(repo_root, "scripts", "tidy.py")),
                 "--merge", shQuote(existing),
                 "--stage", stage, "--teardown", teardown, "--size", size,
                 "--output", shQuote(results_file)),
               log = log_file)
    reports <- c(reports, results_file)
  }

  if (length(console_args)) {
    run_logged("python3",
               c(shQuote(file.path(repo_root, "scripts", "console_summary.py")),
                 "--platform", host, console_args),
               log = log_file)
  }

  # ---- name the run for what it compared ----------------------------------
  compare_label <- paste(vapply(refs[-1], function(ref) {
    label_text <- path_safe(ref)
    if (!identical(versions[[ref]], versions[[ref_first]])) {
      label_text <- paste0(label_text, "-", path_safe(versions[[ref]]))
    }
    label_text
  }, character(1)), collapse = "_vs_")
  if (!nzchar(compare_label)) compare_label <- "alone"
  renamed <- file.path(repo_root, "outputs",
                       paste0(run_date, "_", path_safe(ref_first), "-",
                              path_safe(versions[[ref_first]]), "_vs_", compare_label,
                              label_suffix))
  # The final name carries the version, so an earlier run of the same
  # comparison is replaced here too, not just at the pre-rename path.
  if (dir.exists(renamed) && isTRUE(overwrite) && !identical(renamed, output_dir)) {
    unlink(renamed, recursive = TRUE)
  }
  if (!dir.exists(renamed) && file.rename(output_dir, renamed)) {
    output_dir <- renamed
    run_id <- basename(renamed)
    log_file <- file.path(output_dir, basename(log_file))
  }

  manifest <- data.frame(
    run_id = run_id, label = label, stage = stage, teardown = teardown, size = size,
    ref_first = ref_first, ref_compare = paste(refs[-1], collapse = ","),
    profile = names(status), status = unname(status),
    timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    stringsAsFactors = FALSE)
  utils::write.table(manifest, file.path(output_dir, "manifest.tsv"),
                     sep = "\t", row.names = FALSE, quote = FALSE)

  message("Done: ", output_dir)
  for (path in reports) message("  report: ", basename(path))
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

