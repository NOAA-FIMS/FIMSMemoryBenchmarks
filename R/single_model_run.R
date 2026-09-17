#!/usr/bin/env Rscript
# Sets up the R code to run the FIMS model from `run_fims_benchmark`, runs the
# model once and saves output.
#
#   setup_fims_inputs()  ->  wait for the recorder  ->  setup_fims_model()
#
# The wait matters: profilers that attach to a live process (Instruments) or
# start late (perf -D) begin recording after the inputs are built, so the data
# and the dplyr parameter edits stay out of the recording. Valgrind records from
# the start, which is what the input-only baseline run is for.
#
# Environment:
#   REPO_ROOT             repository root
#   FIMS_STAGE            workflow stage, or "helper" for the end-to-end fit
#   FIMS_BACKEND          "TMB" or "quadra"; a build that cannot provide what
#                         is asked for fails rather than falling back
#   FIMS_SIZE             input size: "normal" (30 years) or "large" (120)
#   VALUES_OUT            where to save what the run computed, as an RDS. Set
#                         only by the unprofiled reference run: it also turns
#                         on the extra values that only that run reports.
#   STAGE_MODE            "stage" runs the rung; "input" stops after the
#                         `fims_setup_input()`` is called, which is the baseline
#                         the report subtracts
#   TEARDOWN              none, clear, or release
#   FIMS_N_EVAL           fn/gr evaluations at stage "evaluate"
#   STAGE_ATTACH_DELAY    seconds to wait once the inputs are ready
#   FIMS_LEAK_COMPLETED   set by scripts/check_leaks.py; written just before exit

source(file.path(Sys.getenv("REPO_ROOT", getwd()), "R", "setup_FIMS.R"))

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

stage <- Sys.getenv("FIMS_STAGE", "initialize")
size <- Sys.getenv("FIMS_SIZE", "normal")
backend <- Sys.getenv("FIMS_BACKEND", "TMB")
values_out <- Sys.getenv("VALUES_OUT")
stage_mode <- Sys.getenv("STAGE_MODE", "stage")
teardown <- Sys.getenv("TEARDOWN", "none")
n_eval <- max(suppressWarnings(as.integer(Sys.getenv("FIMS_N_EVAL", "1"))), 1L, na.rm = TRUE)
attach_delay <- suppressWarnings(as.numeric(Sys.getenv("STAGE_ATTACH_DELAY", "0")))

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
  quit(save = "no", status = 0)
}

if (!is.na(attach_delay) && attach_delay > 0) {
  message("--> Inputs ready; waiting ", attach_delay, "s for the recorder...")
  Sys.sleep(attach_delay)
}

# VALUES_OUT is set only by the unprofiled reference run, so it doubles as
# "compute the extra values the reference run reports". A profiled run leaves it
# empty and measures the workflow stage and nothing else.
record <- nzchar(values_out)

# The memory added by the workflow stage, for the reference run. The kernel's
# high-water mark covers the whole process, so building the data could already
# have set it higher than the stage ever reaches. Writing 5 to clear_refs resets
# it to what the process holds now, so the peak read afterwards belongs to the
# stage. The whole-process peak is kept from before the reset. Linux only.
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
  # mark; Rscript execs the real R binary and exec resets it, so this is R's own
  # peak, start-up and inputs included. Minor and major page faults come from
  # /proc/self/stat, fields 10 and 12. macOS has no /proc, so there
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

# Every run ends with a collection, so what Massif and the leak detector see at
# exit is what the model kept rather than garbage R had not collected yet. The
# peak is unaffected: it happened earlier.
invisible(gc())

# Under a leak detector, scripts/check_leaks.py sets this to tell a run that
# finished from one that crashed.
if (nzchar(Sys.getenv("FIMS_LEAK_COMPLETED"))) {
  writeLines("completed", Sys.getenv("FIMS_LEAK_COMPLETED"))
}

quit(save = "no", status = 0)
