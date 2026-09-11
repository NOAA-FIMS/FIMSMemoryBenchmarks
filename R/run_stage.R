#!/usr/bin/env Rscript
# The workload the C++ profilers record. Runs the model once.
#
#   setup_fims_inputs()  ->  wait for the recorder  ->  setup_fims_model()
#
# The wait matters: profilers that attach to a live process (Instruments) or
# start late (perf -D) begin recording after the fixture is built, so the data
# and the dplyr parameter edits stay out of the recording. Valgrind records from
# the start, which is what the fixture-only baseline run is for.
#
# Environment:
#   REPO_ROOT             repository root
#   FIMS_STAGE            ladder rung, "helper" for the end-to-end fit, or
#                         "validation" for the joint objective comparison
#   FIMS_SIZE             fixture size: "normal" (30 years) or "large" (120)
#   VALIDATION_OUT        where to save the validation RDS
#   STAGE_MODE            "stage" runs the rung; "fixture" stops after the
#                         fixture, which is the baseline the report subtracts
#   TEARDOWN              none, clear, or release
#   FIMS_N_EVAL           fn/gr evaluations at stage "evaluate"
#   STAGE_ATTACH_DELAY    seconds to wait once the fixture is ready
#   STAGE_SIGNATURE_OUT   optional; written after the measured work

source(file.path(Sys.getenv("REPO_ROOT", getwd()), "R", "setup_FIMS.R"))

# FIMS is attached, not just loaded: its DESCRIPTION sets LazyData, so data
# objects such as fims_input_types reach package code through the search path.
# Calling FIMS::FIMSFrame() without this fails with "object 'fims_input_types'
# not found" from inside the package.
#
# Which FIMS this loads is decided by R_LIBS, which the profiler wrapper points
# at this ref's library. Keep no FIMS installed in the user or site library: a
# copy there is a silent fallback, so a half-finished install would measure that
# build instead of the one under test, with nothing in the output to say so.
library(FIMS)

stage <- Sys.getenv("FIMS_STAGE", "initialize")
size <- Sys.getenv("FIMS_SIZE", "normal")
validation_out <- Sys.getenv("VALIDATION_OUT")
stage_mode <- Sys.getenv("STAGE_MODE", "stage")
teardown <- Sys.getenv("TEARDOWN", "none")
n_eval <- max(suppressWarnings(as.integer(Sys.getenv("FIMS_N_EVAL", "1"))), 1L, na.rm = TRUE)
signature_out <- Sys.getenv("STAGE_SIGNATURE_OUT")
attach_delay <- suppressWarnings(as.numeric(Sys.getenv("STAGE_ATTACH_DELAY", "0")))

fixture <- setup_fims_inputs(size = size)

# The baseline run: this process holds the fixture and nothing the interface
# allocated, so subtracting it leaves what the stage is responsible for.
if (identical(stage_mode, "fixture")) {
  quit(save = "no", status = 0)
}

if (!is.na(attach_delay) && attach_delay > 0) {
  message("--> Fixture ready; waiting ", attach_delay, "s for the recorder...")
  Sys.sleep(attach_delay)
}

result <- if (identical(stage, "helper")) {
  list(signature = list(), fit = run_fims_helper(fixture))
} else if (identical(stage, "validation")) {
  # The joint objective fit. Saved as RDS because R/summarize_validation.R and
  # the final reports read the whole structure, not a summary of it.
  validation <- run_fims_validation(fixture)
  if (nzchar(validation_out)) {
    saveRDS(validation, validation_out)
    message("--> Validation result written to ", validation_out)
  }
  list(signature = list(nll = validation$final_objective), validation = validation)
} else {
  setup_fims_model(fixture, stage = stage, teardown = teardown, n_eval = n_eval)
}

# Written after the measured work, so it cannot affect the peak.
if (nzchar(signature_out)) {
  count_or_na <- function(expr) tryCatch(length(expr), error = function(e) NA_integer_)
  values <- c(
    stage = stage,
    teardown = teardown,
    n_fixed = count_or_na(FIMS::get_fixed()),
    n_random = count_or_na(FIMS::get_random()),
    n_par = if (is.null(result$signature$n_par)) NA_integer_ else result$signature$n_par,
    nll = if (is.null(result$signature$nll)) NA_character_ else format(result$signature$nll, digits = 12)
  )
  utils::write.table(
    data.frame(key = names(values), value = as.character(values), stringsAsFactors = FALSE),
    signature_out, sep = "\t", row.names = FALSE, quote = FALSE)
}

quit(save = "no", status = 0)
