# A stand-in for FIMS with just enough surface for setup_fims_model() to run
# its initialize rung. The rungs above it need TMB's compiled tape, which only a
# real build has. Setting STUB_FIMS_LEAK=1 makes every model build keep 1 MB
# for good, which is what the back-to-back test has to detect.
.state <- new.env()
.state$kept <- list()

clear <- function() {
  .state$fixed <- NULL
  .state$random <- NULL
  invisible(NULL)
}

initialize_fims <- function(parameters, data) {
  .state$fixed <- c(0.5, -1.2, 2.0)
  .state$random <- c(0.01, 0.02)
  # Temporary garbage, as a real build makes.
  work <- numeric(262144)
  if (identical(Sys.getenv("STUB_FIMS_LEAK"), "1")) {
    .state$kept[[length(.state$kept) + 1L]] <- numeric(131072)
  }
  list(parameters = list(p = .state$fixed, re = .state$random))
}

CreateTMBModel <- function() invisible(NULL)
get_fixed <- function() .state$fixed
get_random <- function() .state$random
