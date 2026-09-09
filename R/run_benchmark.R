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

# Memory profiling wants unoptimized, unstripped frames; CPU profiling wants
# optimized code that still has symbols. R reads R_MAKEVARS_USER in place of
# ~/.R/Makevars, so the shared file is never touched.
BUILD_FLAGS <- list(
  debug = c("PKG_CXXFLAGS += -g -O0 -fno-omit-frame-pointer -fvisibility=default",
            "PKG_STRIP = true"),
  profile = c("PKG_CXXFLAGS += -g -O2 -fno-omit-frame-pointer -fvisibility=default",
              "PKG_STRIP = true")
)

path_safe <- function(value) gsub("[^A-Za-z0-9._-]", "_", value)


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
  run_date <- format(Sys.time(), "%Y%m%d", tz = "UTC")
  output_dir <- file.path(repo_root, "outputs",
                          paste0(run_date, "_", path_safe(ref_first),
                                 "_vs_", path_safe(ref_compare)))
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
    makevars <- file.path(output_dir, paste0("Makevars.", build_type))
    writeLines(BUILD_FLAGS[[build_type]], makevars)

    for (ref in refs) {
      lib <- file.path(output_dir, "lib", build_type, path_safe(ref))
      dir.create(lib, recursive = TRUE, showWarnings = FALSE)
      env <- c(paste0("R_LIBS_USER=", shQuote(lib)),
               paste0("R_MAKEVARS_USER=", shQuote(makevars)),
               "R_REMOTES_UPGRADE=never",
               paste0("REPO_ROOT=", shQuote(repo_root)),
               paste0("FIMS_REF=", shQuote(ref)))

      message("  installing ", ref, " (", build_type, ")")
      code <- system2("Rscript",
                      c("-e", shQuote(paste0("source(file.path(Sys.getenv('REPO_ROOT'), 'R', 'setup_FIMS.R')); ",
                                             "install_fims_debug(Sys.getenv('FIMS_REF'))"))),
                      env = env, stdout = log_file, stderr = log_file)
      if (code != 0L) {
        stop("Installing '", ref, "' (", build_type, ") failed; see ", log_file, call. = FALSE)
      }

      version <- tail(system2("Rscript",
                              c("-e", shQuote("cat(as.character(packageVersion('FIMS')))")),
                              env = env, stdout = TRUE), 1L)

      builds[[build_type]][[ref]] <- list(lib = lib, version = version)
    }
  }

  versions <- vapply(refs, function(ref) builds[[build_types[[1]]]][[ref]]$version,
                     character(1))

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
    if (capture) {
      out <- suppressWarnings(system2("bash", args, stdout = TRUE, stderr = log_file))
      if (length(out)) tail(out, 1L) else "failed"
    } else {
      system2("bash", args, stdout = log_file, stderr = log_file)
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
        if (code != 0L) memory_status <- code
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
      if (code != 0L) memory_status <- code
      add_input(kind, ref, stage, 1L, "", out)
    }
    status[["memory"]] <- memory_status
  }

  if ("cpu" %in% profiles) {
    tool <- if (identical(host, "Darwin")) "instruments" else "perf"
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
      add_input("cpu-status", ref, stage, 1L, state, report)
      if (grepl("^captured", state)) {
        add_input(if (tool == "perf") "perf" else "instruments-cpu",
                  ref, stage, 1L, "", report)
      }
    }
    status[["cpu"]] <- 0L
  }

  # ---- collect and report -------------------------------------------------
  inputs_file <- file.path(output_dir, "inputs.tsv")
  results_file <- file.path(output_dir, "results.tsv")
  report_file <- file.path(output_dir, "report.md")

  utils::write.table(do.call(rbind, inputs), inputs_file, sep = "\t",
                     row.names = FALSE, quote = FALSE)
  collected <- system2("python3",
                       c(shQuote(file.path(repo_root, "scripts", "collect.py")),
                         "--inputs", shQuote(inputs_file),
                         "--teardown", teardown,
                         "--output", shQuote(results_file)),
                       stdout = log_file, stderr = log_file)

  if (collected == 0L && file.exists(results_file)) {
    signature_args <- unlist(lapply(names(signatures), function(ref) {
      if (file.exists(signatures[[ref]])) c("--signature", shQuote(ref), shQuote(signatures[[ref]]))
    }))
    system2("python3",
            c(shQuote(file.path(repo_root, "scripts", "report.py")),
              "--results", shQuote(results_file),
              "--stage", stage, "--teardown", teardown,
              "--platform", host, "--run-id", shQuote(run_id),
              signature_args,
              "--output", shQuote(report_file)),
            stdout = log_file, stderr = log_file)
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
  if (!dir.exists(renamed) && file.rename(output_dir, renamed)) {
    output_dir <- renamed
    run_id <- basename(renamed)
    if (!is.na(report_file)) report_file <- file.path(output_dir, basename(report_file))
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
  invisible(output_dir)
}

