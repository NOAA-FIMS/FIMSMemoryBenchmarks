# ---------------------------------------------------------------------------
# Fixture: everything identical across branches. Built once, never timed.
# ---------------------------------------------------------------------------

make_fims_fixture <- function() {
  data_big <- NULL
  utils::data("data_big", package = "FIMS", envir = environment())
  data_4_model <- FIMS::FIMSFrame(data_big)

  parameters_4_model <- FIMS::setup_default_parameters(data = data_4_model) |>
    dplyr::rows_update(
      tibble::tibble(
        fleet = "fleet1",
        label = "log_Fmort",
        timing = seq(FIMS::get_n_years(data_4_model)),
        value = log(c(
          0.009459165, 0.027288858, 0.045063639, 0.061017825, 0.048600752,
          0.087420554, 0.088447204, 0.186607929, 0.109008958, 0.132704335,
          0.150615473, 0.161242955, 0.116640187, 0.169346119, 0.180191913,
          0.161240483, 0.314573212, 0.257247574, 0.254887252, 0.251462108,
          0.349101406, 0.254107720, 0.418478117, 0.345721184, 0.343685540,
          0.314171227, 0.308026829, 0.431745298, 0.328030899, 0.499675368
        ))
      ),
      by = c("fleet", "label", "timing")
    ) |>
    dplyr::rows_update(
      tibble::tibble(
        fleet = "survey1",
        label = c("inflection_point", "slope", "log_q"),
        value = c(1.5, 2, log(3.315143e-07))
      ),
      by = c("fleet", "label")
    ) |>
    dplyr::rows_update(
      tibble::tibble(
        label = "log_devs",
        timing = 2:FIMS::get_n_years(data_4_model),
        value = c(
          0.43787763, -0.13299042, -0.43251973, 0.64861200, 0.50640852,
          -0.06958319, 0.30246260, -0.08257384, 0.20740372, 0.15289604,
          -0.21709207, -0.13320626, 0.11225374, -0.10650836, 0.26877132,
          0.24094126, -0.54480751, -0.23680557, -0.58483386, 0.30122785,
          0.21930545, -0.22281699, -0.51358369, 0.15740234, -0.53988240,
          -0.19556523, 0.20094360, 0.37248740, -0.07163145
        )
      ),
      by = c("label", "timing")
    ) |>
    dplyr::rows_update(
      tibble::tibble(
        module_name = "Recruitment", label = "log_sd", value = 0.4
      ),
      by = c("module_name", "label")
    ) |>
    dplyr::rows_update(
      tibble::tibble(
        module_name = "Maturity",
        label = c("inflection_point", "slope"),
        value = c(2.25, 3)
      ),
      by = c("module_name", "label")
    ) |>
    dplyr::rows_update(
      tibble::tibble(
        label = "log_init_naa",
        age = seq(FIMS::get_n_ages(data_4_model)),
        value = c(
          13.80944, 13.60690, 13.40217, 13.19525, 12.98692, 12.77791,
          12.56862, 12.35922, 12.14979, 11.94034, 11.73088, 13.18755
        )
      ),
      by = c("label", "age")
    )

  list(data = data_4_model, parameters = parameters_4_model)
}


# ---------------------------------------------------------------------------
# Staged runner
# ---------------------------------------------------------------------------

#' @param stage    How far up the ladder to run. Cumulative.
#' @param teardown Orthogonal to stage. "release" drops R handles and calls
#'   gc() WITHOUT clear(), which is the GC-driven path XPtr claims and the
#'   native approach does not currently provide.
#' @param n_eval   Number of fn/gr evaluations at fixed theta. Use > 1 to lift
#'   evaluation cost above timer resolution.
#' @param theta    Fixed parameter vector. Pass the same one to both branches
#'   so evaluation cost is compared at an identical point.
run_fims_stages <- function(fixture,
                            stage = c("initialize", "assemble", "tape",
                                      "evaluate", "optimize", "sdreport"),
                            teardown = c("none", "clear", "release"),
                            n_eval = 1L,
                            theta = NULL,
                            random = "re") {
  stage <- match.arg(stage)
  teardown <- match.arg(teardown)
  ladder <- c("initialize", "assemble", "tape", "evaluate", "optimize", "sdreport")
  target <- match(stage, ladder)

  marks <- c(enter = bench::hires_time())
  mark <- function(nm) marks[[nm]] <<- bench::hires_time()

  FIMS::clear()
  mark("clear_entry")

  # --- initialize: construction + the first assembly pass ------------------
  init_parms <- FIMS::initialize_fims(fixture$parameters, data = fixture$data)
  mark("initialize")

  # --- assemble: a second CreateTMBModel() re-runs assembly over the SAME
  # interface objects, so (initialize - assemble) isolates construction cost
  # without needing a `build = FALSE` argument upstream. Verify the guard
  # below holds on both branches before trusting the decomposition.
  if (target >= 2L) {
    n_before <- length(FIMS::get_fixed())
    FIMS::CreateTMBModel()
    stopifnot(length(FIMS::get_fixed()) == n_before)
    mark("assemble")
  }

  obj <- NULL
  signature <- list()

  if (target >= 3L) {
    obj <- TMB::MakeADFun(
      data = list(),
      parameters = init_parms$parameters,
      random = random,
      DLL = "FIMS",
      silent = TRUE
    )
    mark("tape")
    signature$par_names <- names(obj$par)
    signature$n_par <- length(obj$par)
  }

  if (target >= 4L) {
    if (is.null(theta)) theta <- obj$par
    for (i in seq_len(n_eval)) {
      nll <- obj$fn(theta)
      gr <- obj$gr(theta)
    }
    mark("evaluate")
    signature$nll <- nll
    signature$gradient <- as.numeric(gr)
  }

  if (target >= 5L) {
    opt <- nlminb(
      start = if (is.null(theta)) obj$par else theta,
      objective = obj$fn, gradient = obj$gr,
      control = list(eval.max = 10000, iter.max = 10000, trace = 0)
    )
    mark("optimize")
    signature$objective <- opt$objective
    signature$iterations <- opt$iterations
    signature$convergence <- opt$convergence
  }

  if (target >= 6L) {
    sdr <- TMB::sdreport(obj)
    mark("sdreport")
    signature$sd_par_fixed <- as.numeric(sqrt(diag(sdr$cov.fixed)))
  }

  switch(teardown,
    clear   = { FIMS::clear(); mark("teardown") },
    release = { obj <- NULL; init_parms <- NULL; gc(); mark("teardown") },
    none    = invisible(NULL)
  )

  structure(
    list(signature = signature,
         phases = diff(marks),
         stage = stage,
         teardown = teardown),
    class = "fims_stage_result"
  )
}


# ---------------------------------------------------------------------------
# End-to-end path, kept separate because it does not share the ladder
# ---------------------------------------------------------------------------

run_fims_helper <- function(fixture) {
  FIMS::clear()
  init_parms <- FIMS::initialize_fims(fixture$parameters, data = fixture$data)
  fit <- FIMS::fit_fims(init_parms, optimize = TRUE)
  on.exit(FIMS::clear(), add = TRUE)
  invisible(fit)
}


# ---------------------------------------------------------------------------
# Equivalence check for bench::mark(check = fims_check)
# ---------------------------------------------------------------------------

fims_check <- function(a, b) {
  fa <- a$signature
  fb <- b$signature
  identical(fa$par_names, fb$par_names) &&
    isTRUE(all.equal(fa$nll, fb$nll, tolerance = 1e-8)) &&
    isTRUE(all.equal(fa$gradient, fb$gradient, tolerance = 1e-6))
}

# ---------------------------------------------------------------------------
# Installation
# ---------------------------------------------------------------------------

#' Install one FIMS ref from source
#'
#' The compiler flags come from the environment, not from this function:
#' run_fims_benchmark() writes a Makevars per build type and points
#' R_MAKEVARS_USER at it, so the same call produces the -O0 build for Valgrind
#' and the -O2 build for perf. R_LIBS_USER decides which library it lands in, so
#' both builds of both refs can coexist.
#'
#' `--preclean` runs `make clean` in the package source before building. It is a
#' no-op when remotes downloads a fresh copy, but it is what stops a local
#' checkout from linking object files left over from a build with different
#' flags -- which would silently mix -O0 and -O2 objects in one library.
#'
#' @param ref Branch name, tag, or commit hash (e.g. "main", "xptr-refactor").
install_fims_debug <- function(ref = "main") {
  message(sprintf("Installing NOAA-FIMS/FIMS@%s ...", ref))

  if (!requireNamespace("remotes", quietly = TRUE)) {
    install.packages("remotes")
  }

  remotes::install_github(
    repo = "NOAA-FIMS/FIMS",
    ref = ref,
    force = TRUE,
    build_vignettes = FALSE,
    INSTALL_opts = c("--no-multiarch", "--preclean")
  )
}
