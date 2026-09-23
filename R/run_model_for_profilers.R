# The two ways the benchmark runs the FIMS model, one function each:
#
#   run_model_for_cpp_profiler()   the model once, to one stage. Massif, perf,
#                                  Instruments and the leak detector record it,
#                                  and the reference run runs it with nothing
#                                  attached.
#   run_model_for_R_profiler()     the model built, run and cleared repeatedly,
#                                  for memory growth and bench::mark() timing.
#
# setup_fims_inputs()  ->  wait for the recorder  ->  setup_fims_model()
#
# The wait matters: profilers that attach to a live process (Instruments) or
# start late (perf -D) begin recording after the inputs are built, so the data
# and the dplyr parameter edits stay out of the recording. Valgrind records from
# the start, which is what the input-only baseline run is for.
#
# This file only defines the two functions. Each call runs in its own process,
# because two FIMS builds cannot share a session and a profiler has to own the
# process it records, so every launcher starts a fresh Rscript that sources this
# file and calls one of them:
#
#   Rscript -e "source(file.path(Sys.getenv('REPO_ROOT'), 'R',
#                                'run_model_for_profilers.R')); run_model_for_cpp_profiler()"
#
# Every argument defaults to the environment variable run_fims_benchmark() sets,
# so the launchers pass nothing. Interactively, point R at one build and call
# either function with whatever you want to override:
#
#   .libPaths(c("outputs/.lib-cache/profile/main", .libPaths()))
#   source("R/run_model_for_profilers.R")
#   result <- run_model_for_cpp_profiler(stage = "tape", size = "large")
#   rows <- run_model_for_R_profiler(stage = "tape", iterations = 5)

#' Run the FIMS model once, to one stage
#'
#' Every argument defaults to the environment variable run_fims_benchmark()
#' sets, so the pipeline passes nothing and an interactive call can override
#' any of them.
#'
#' @param stage Workflow stage, or "helper" for the end-to-end fit.
#' @param size Input size: "normal" (30 years) or "large" (120).
#' @param backend "TMB" or "quadra"; a build that cannot provide what is asked
#'   for fails rather than falling back.
#' @param teardown "none", "clear", or "release".
#' @param n_eval fn/gr evaluations at stage "evaluate".
#' @param values_out Where to save what the run computed, as an RDS. Set only by
#'   the unprofiled reference run: it also turns on the extra values that only
#'   that run reports.
#' @param stage_mode "stage" runs the rung; "inputs" stops after
#'   setup_fims_inputs(), which is the baseline the report subtracts.
#' @param attach_delay Seconds to wait once the inputs are ready.
#' @param leak_marker Set by scripts/check_leaks.py; written just before the
#'   function returns, so a finished run can be told apart from a crash.
#' @param repo_root Repository root, for setup_FIMS.R.
#' @return The setup_fims_model() result, invisibly; NULL for the baseline run.
run_model_for_cpp_profiler <- function(
    stage = Sys.getenv("FIMS_STAGE", "initialize"),
    size = Sys.getenv("FIMS_SIZE", "normal"),
    backend = Sys.getenv("FIMS_BACKEND", "TMB"),
    teardown = Sys.getenv("TEARDOWN", "none"),
    n_eval = Sys.getenv("FIMS_N_EVAL", "1"),
    values_out = Sys.getenv("VALUES_OUT"),
    stage_mode = Sys.getenv("STAGE_MODE", "stage"),
    attach_delay = Sys.getenv("STAGE_ATTACH_DELAY", "0"),
    leak_marker = Sys.getenv("FIMS_LEAK_COMPLETED"),
    repo_root = Sys.getenv("REPO_ROOT", getwd())) {
  source(file.path(repo_root, "R", "setup_FIMS.R"))

  # FIMS is attached, not just loaded: its DESCRIPTION sets LazyData, so data
  # objects such as fims_input_types reach package code through the search path.
  # Calling FIMS::FIMSFrame() without this fails with "object 'fims_input_types'
  # not found" from inside the package.
  #
  # The branch of FIMS that is loaded is decided by R_LIBS, which specifies the
  # location of where the branch-specific library is stored. The profiler wrapper
  # then points to this location to load the correct library.
  # **Do not install a version of FIMS locally to the user or site library: a
  # copy there is a silent fallback, so a half-finished install of a branch under
  # test would silently fall back to the locally installed version therefore
  # silently comparing the wrong branch.
  library(FIMS)

  n_eval <- max(suppressWarnings(as.integer(n_eval)), 1L, na.rm = TRUE)
  attach_delay <- suppressWarnings(as.numeric(attach_delay))

  # A /proc/self/status field in kilobytes, or NA where there is no /proc (macOS).
  proc_kb <- function(name) {
    if (!file.exists("/proc/self/status")) return(NA_real_)
    line <- grep(paste0("^", name, ":"), readLines("/proc/self/status"), value = TRUE)
    if (length(line)) as.numeric(gsub("[^0-9]", "", line[[1]])) else NA_real_
  }

  inputs <- setup_fims_inputs(size = size)

  # The baseline run: this process measures the cost of setting up the model
  # inputs, which are then subtracted from the workflow stage of interest.
  if (identical(stage_mode, "inputs")) {
    return(invisible(NULL))
  }

  if (!is.na(attach_delay) && attach_delay > 0) {
    message("--> Inputs ready; waiting ", attach_delay, "s for the recorder...")
    Sys.sleep(attach_delay)
  }

  # values_out is set only by the unprofiled reference run, so it doubles as
  # "compute the extra values the reference run reports". A profiled run leaves
  # it empty and measures the workflow stage and nothing else.
  record <- nzchar(values_out)

  # The memory added by the workflow stage, for the reference run. The kernel's
  # high-water mark covers the whole process, so building the data could already
  # have set it higher than the stage ever reaches. Writing 5 to clear_refs
  # resets it to what the process holds now, so the peak read afterwards belongs
  # to the stage. The whole-process peak is kept from before the reset. Linux only.
  peak_before_stage <- NA_real_
  rss_at_stage_start <- NA_real_
  if (record && file.exists("/proc/self/clear_refs")) {
    invisible(gc())
    peak_before_stage <- proc_kb("VmHWM")
    reset <- tryCatch({ writeLines("5", "/proc/self/clear_refs"); TRUE },
                      error = function(e) FALSE, warning = function(w) FALSE)
    if (isTRUE(reset)) rss_at_stage_start <- proc_kb("VmRSS")
  }

  result <- setup_fims_model(inputs, stage = stage, teardown = teardown,
                             n_eval = n_eval, backend = backend, record = record)

  # What the run computed, saved whole because the reports read the structure
  # rather than a summary.
  if (record) {
    values <- result$result
    values$stage <- stage
    values$model_size <- size
    # Peak resident memory, from the kernel. VmHWM is this process's high-water
    # mark; Rscript execs the real R binary and exec resets it, so this is R's
    # own peak, start-up and inputs included. Minor and major page faults come
    # from /proc/self/stat, fields 10 and 12. macOS has no /proc, so there
    # run_benchmark.R wraps this run in /usr/bin/time instead.
    if (file.exists("/proc/self/status")) {
      peak_after <- proc_kb("VmHWM")
      values$maximum_rss <- max(peak_before_stage, peak_after, na.rm = TRUE) * 1024
      if (!is.na(rss_at_stage_start)) {
        values$stage_rss_added <- max(peak_after - rss_at_stage_start, 0) * 1024
      }
      stat <- readLines("/proc/self/stat", warn = FALSE)
      fields <- strsplit(trimws(sub("^.*\\) ", "", stat)), "\\s+")[[1]]
      # Counting from field 3, the first after the command name in parentheses.
      values$page_reclaims <- as.numeric(fields[[10L - 2L]])
      values$page_faults <- as.numeric(fields[[12L - 2L]])
    }
    saveRDS(values, values_out)
    message("--> Values written to ", values_out)
  }

  # Every run ends with a collection, so what Massif and the leak detector see
  # at exit is what the model kept rather than garbage R had not collected yet.
  # The peak is unaffected: it happened earlier.
  invisible(gc())

  # Under a leak detector, scripts/check_leaks.py sets this to tell a run that
  # finished from one that crashed.
  if (nzchar(leak_marker)) {
    writeLines("completed", leak_marker)
  }

  invisible(result)
}

#' Build, run and clear the model repeatedly; measure memory growth and time
#'
#' Every argument defaults to the environment variable run_fims_benchmark()
#' sets, so the pipeline passes nothing and an interactive call can override
#' any of them.
#'
#' @param stage,size,backend As for setup_fims_model() and setup_fims_inputs().
#' @param iterations Cycles in each loop; at least 3, so there is a slope to fit.
#' @param out Where to write the tidy rows. Empty writes nothing, which is
#'   convenient interactively.
#' @param ref,version Labels for the rows.
#' @param repo_root Repository root, for setup_FIMS.R and the memory helper.
#' @return The tidy rows, invisibly.
run_model_for_R_profiler <- function(stage = Sys.getenv("FIMS_STAGE", "initialize"),
                                     size = Sys.getenv("FIMS_SIZE", "normal"),
                                     backend = Sys.getenv("FIMS_BACKEND", "TMB"),
                                     teardown = Sys.getenv("TEARDOWN", "none"),
                                     iterations = Sys.getenv("BENCH_ITERATIONS", "20"),
                                     out = Sys.getenv("BENCH_OUT"),
                                     ref = Sys.getenv("BENCH_REF"),
                                     version = Sys.getenv("BENCH_VERSION"),
                                     repo_root = Sys.getenv("REPO_ROOT", getwd())) {
  source(file.path(repo_root, "R", "setup_FIMS.R"))
  # Attached, not just loaded, and chosen by R_LIBS: see
  # run_model_for_cpp_profiler() above.
  library(FIMS)
  iterations <- max(suppressWarnings(as.integer(iterations)), 3L, na.rm = TRUE)

  # glibc's count, from a two-line C helper compiled here. Building FIMS already
  # needs a compiler, so this adds no dependency.
  heap_in_use <- NULL
  if (identical(Sys.info()[["sysname"]], "Linux")) {
    build <- file.path(tempdir(), "heap_in_use")
    dir.create(build, showWarnings = FALSE)
    file.copy(file.path(repo_root, "scripts", "heap_in_use.c"), build, overwrite = TRUE)
    previous <- setwd(build)
    status <- system2(file.path(R.home("bin"), "R"), c("CMD", "SHLIB", "heap_in_use.c"),
                      stdout = FALSE, stderr = FALSE)
    setwd(previous)
    helper <- file.path(build, paste0("heap_in_use", .Platform$dynlib.ext))
    if (identical(as.integer(status), 0L) && file.exists(helper)) {
      if (!is.loaded("heap_in_use")) dyn.load(helper)
      heap_in_use <- function() .Call("heap_in_use")
    } else {
      warning("Could not compile the memory helper, so memory growth is not measured.",
              call. = FALSE)
    }
  }

  # Three garbage collections before every reading: objects with finalizers,
  # such as those behind external pointers, are released a collection late, so
  # a single pass leaves them counted.
  call_gc <- function() for (i in 1:3) invisible(gc())

  inputs <- setup_fims_inputs(size = size)
  # The cycle tears down the way its run does. Every cycle also begins with
  # clear(), inside setup_fims_model(), so the previous model is gone either
  # way: what the teardown changes is whether a model is still alive when the
  # reading is taken, which shows in the level, not the slope. The slope is the
  # leak, and it is a leak under any teardown.
  cycle <- function() {
    invisible(setup_fims_model(inputs, stage = stage, teardown = teardown,
                               backend = backend))
  }

  # --- 1. does memory accumulate? -------------------------------------------
  in_use <- rep(NA_real_, iterations)
  if (!is.null(heap_in_use)) {
    for (i in seq_len(iterations)) {
      cycle()
      call_gc()
      in_use[[i]] <- heap_in_use()
    }
  }
  # The first two cycles carry one-time costs -- modules loaded and caches
  # filled on first use -- so the slope is taken over the cycles after them.
  settled <- in_use[-(1:2)]
  growth <- if (sum(is.finite(settled)) >= 3L) {
    unname(stats::coef(stats::lm(settled ~ seq_along(settled)))[[2]])
  } else {
    NA_real_
  }

  # --- 2. how long does it take? --------------------------------------------
  # filter_gc = FALSE keeps every iteration: garbage collection is part of what
  # the stage costs, and dropping those iterations would flatter it.
  timing <- suppressWarnings(bench::mark(
    cycle(), iterations = iterations, check = FALSE, filter_gc = FALSE,
    time_unit = "s", memory = isTRUE(unname(capabilities("profmem")))))
  times <- as.numeric(timing$time[[1]])
  collections <- rowSums(as.data.frame(timing$gc[[1]]))
  allocated <- as.numeric(timing$mem_alloc)

  # --- rows -------------------------------------------------------------------
  as_text <- function(x) {
    if (is.finite(x) && x == round(x) && abs(x) < 1e15) {
      formatC(x, format = "f", digits = 0L)
    } else {
      format(x, digits = 15L)
    }
  }
  row <- function(metric, unit, value, iteration = "") {
    data.frame(metric = metric, unit = unit, value = as_text(value),
               iteration = as.character(iteration), stringsAsFactors = FALSE)
  }
  rows <- rbind(
    row("cycles", "count", iterations),
    if (!is.null(heap_in_use)) rbind(
      row("heap_growth_per_cycle", "bytes", growth),
      row("heap_after_first_cycle", "bytes", in_use[[1L]]),
      row("heap_after_last_cycle", "bytes", in_use[[iterations]]),
      do.call(rbind, lapply(seq_len(iterations), function(i) {
        row("heap_after_cycle", "bytes", in_use[[i]], i)
      }))
    ),
    row("median_time", "seconds", stats::median(times)),
    row("gc_per_cycle", "count", stats::median(collections)),
    if (length(allocated) == 1L && is.finite(allocated)) row("mem_alloc", "bytes", allocated),
    do.call(rbind, lapply(seq_along(times), function(i) row("time", "seconds", times[[i]], i)))
  )
  # "lifecycle" is what R/report.R looks for: the rows cover the memory loop as
  # well as bench::mark().
  rows <- data.frame(
    ref = ref, fims_version = version,
    stage = "", backend = "", teardown = "", size = "", round = "",
    iteration = rows$iteration, source = "lifecycle", metric = rows$metric,
    unit = rows$unit, value = rows$value, path = "", stringsAsFactors = FALSE)
  if (nzchar(out)) {
    utils::write.table(rows, out, sep = "\t", row.names = FALSE, quote = FALSE)
    message("--> ", iterations, " back-to-back cycles written to ", out)
  }
  invisible(rows)
}
