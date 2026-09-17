check_for_quadra <- function() {
  if (!exists("quadra_fit")) {
    stop("The current branch is not built to work with quadra. ",
    "Please provide a branch where quandra is built into the backend.")
  }
}

# ---------------------------------------------------------------------------
# Model size and backend support, ported verbatim from
# feature/macos-instruments-profiling so the upstream reporting keeps working.
# ---------------------------------------------------------------------------

expand_fims_years <- function(dat, n_years) {
  base_years <- get_n_years(dat)
  static <- dat |> get_data() |>
    dplyr::filter(type == "age_to_length_conversion")
  dynamic_types <- dat |> get_data() |>
    dplyr::filter(type != "age_to_length_conversion") |>
    dplyr::pull(type) |> unique()
  expanded <- lapply(dynamic_types, function(typename) {
    source_dat <- dat |> get_data() |> dplyr::filter(type == typename)
    if (typename == "weight_at_age") {
      source_years <- base_years + 1L
      target_years <- n_years + 1L
    } else {
      source_years <- base_years
      target_years <- n_years
    }
    do.call(rbind, lapply(seq_len(target_years), function(year) {
      source_year <- (year - 1L) %% source_years + 1L
      rows <- source_dat |> dplyr::filter(timing == source_year)
      rows$timing <- year
      rows
    }))
  })
  result <- do.call(rbind, c(list(static), expanded))
  rownames(result) <- NULL
  result
}

expand_fims_modules <- function(parameters, n_fleets, n_surveys) {

}

setup_fims_inputs <- function(size = c("normal", "large")) {
  size <- match.arg(size)

  if (size == "normal") {
    n_years <- 30
  } else {
    n_years <- 120
  }

  data("data_big")
  data_big <- FIMS::FIMSFrame(data_big)

  # "normal" is the current number of years of data_big (30 years). Longer models are built by
  # recycling its years, so the model grows in dimension while values repeat across added years

  benchmark_data <- if (n_years > 30L) expand_fims_years(data_big, n_years) else data_big
  message(sprintf("--> Inputs: %s (%d years)", size, n_years))
  data_4_model <- FIMS::FIMSFrame(benchmark_data)

  parameters_4_model <- FIMS::setup_default_parameters(data = data_4_model) |>
    dplyr::rows_update(
      tibble::tibble(
        fleet = "fleet1",
        label = "log_Fmort",
        timing = seq(FIMS::get_n_years(data_4_model)),
        value = log(rep(c(
          0.009459165, 0.027288858, 0.045063639, 0.061017825, 0.048600752,
          0.087420554, 0.088447204, 0.186607929, 0.109008958, 0.132704335,
          0.150615473, 0.161242955, 0.116640187, 0.169346119, 0.180191913,
          0.161240483, 0.314573212, 0.257247574, 0.254887252, 0.251462108,
          0.349101406, 0.254107720, 0.418478117, 0.345721184, 0.343685540,
          0.314171227, 0.308026829, 0.431745298, 0.328030899, 0.499675368
        ), length.out = FIMS::get_n_years(data_4_model)))
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
        value = rep(c(
          0.43787763, -0.13299042, -0.43251973, 0.64861200, 0.50640852,
          -0.06958319, 0.30246260, -0.08257384, 0.20740372, 0.15289604,
          -0.21709207, -0.13320626, 0.11225374, -0.10650836, 0.26877132,
          0.24094126, -0.54480751, -0.23680557, -0.58483386, 0.30122785,
          0.21930545, -0.22281699, -0.51358369, 0.15740234, -0.53988240,
          -0.19556523, 0.20094360, 0.37248740, -0.07163145
        ), length.out = FIMS::get_n_years(data_4_model) - 1L)
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

  list(data = data_4_model, parameters = parameters_4_model,
       size = size, n_years = n_years)
}


# ---------------------------------------------------------------------------
# FIMS model run to different stages of the fit workflow
# ---------------------------------------------------------------------------

#' @param stage    How much of the workflow to run. Cumulative.
#' @param teardown Orthogonal to stage. "release" drops R handles and calls
#'   gc() WITHOUT clear(), which is the GC-driven path XPtr claims and the
#'   native approach does not currently provide.
#' @param n_eval   Number of fn/gr evaluations at fixed theta. Use > 1 to lift
#'   evaluation cost above timer resolution.
#' @param theta    Fixed parameter vector. Pass the same one to both branches
#'   so evaluation cost is compared at an identical point.
#' Run the model up one stage of the workflow
#'
#' The stages are cumulative: "sdreport" runs everything below it. Each stage is
#' timed separately, so one run yields the cost of every stage beneath it.
#'
#' `backend` chooses the model used to build the tape (TMB vs. Quadra).
#' TMB builds an AD tape with MakeADFun and optimizes over it; Quadra
#' builds its own model from the FIMS modules and runs its own tape, so
#' the quadra path skips the 'tape' stage entirely. After the 'tape'
#' stage, the Quadra and TMB runs are identical.
#'
#' From "optimize" the run also records what is needed to check that two builds
#' agree -- objective, gradient, parameters, convergence -- and at "sdreport"
#' the standard errors.
#'
#' @param input Output of setup_fims_inputs().
#' @param stage The stopping point of the model run.
#' @param teardown "none" leaves the objects alive, "clear" calls FIMS::clear(),
#'   "release" drops handles and runs the garbage collector.
#' @param n_eval fn/gr evaluations at the "evaluate" rung.
#' @param backend "TMB" or "quadra". 
#' @param record False by default. Results are only recorded in the reference run
#' outside the R and C++ profiler runs.
#' @return A list of phase timings, results, and arguments used for the run.
setup_fims_model <- function(input,
                             stage = c("initialize", "tape", "evaluate",
                                        "optimize", "sdreport", "helper"),
                             teardown = c("none", "clear", "release"),
                             n_eval = 1L,
                             backend = c("TMB", "quadra"),
                             record = FALSE) {
  stage <- match.arg(stage)
  teardown <- match.arg(teardown)
  backend <- match.arg(backend)

  marks <- c(enter = bench::hires_time())
  mark <- function(nm) marks[[nm]] <<- bench::hires_time()
  result <- list(backend = backend)

  if (stage == "helper") {
    if (backend == "quadra") {
      check_for_quadra()
    }
    FIMS::clear()
    mark("clear_entry")
    init_parms <- FIMS::initialize_fims(
      result$parameters, data = result$data
    )
    fit <- FIMS::fit_fims(init_parms, optimize = TRUE,
                          backend = backend)
    result = fit

  } else {
    ladder <- c("initialize", "tape", "evaluate",
                "optimize", "sdreport")
    target <- match(stage, ladder)

    FIMS::clear()
    mark("clear_entry")

    # --- initialize: construction, and CreateTMBModel() inside initialize_fims(),
    # which populates the derived quantities -------------------------------------
    init_parms <- FIMS::initialize_fims(input$parameters, data = input$data)
    mark("initialize")
    if (record) {
      result$initial_parameters <- init_parms$parameters
      result$n_fixed <- init_parms$parameters$p |> length()
      result$n_random <- init_parms$parameters$re |> length()
      result$n_par <- init_parms$parameters |> unlist() |> length()
    }

    obj <- NULL

    # --- tape: 
    if (target >= 2L) {
      obj <- TMB::MakeADFun(
        data = list(), parameters = init_parms$parameters,
        random = "re", DLL = "FIMS", silent = TRUE
      )
      mark("tape")
      if (record) {
        result$n_par <- length(obj$env$last.par.best)
        result$initial_parameters <- obj$env$last.par.best
      }
    }

    # --- evaluate
    if (target >= 3L) {
      initial_nll <- initial_gr <- 0
      for (i in seq_len(n_eval)) {
        nll <- obj$fn(obj$par)
        gradient <- obj$gr(obj$par)
        if (i == 1) {
          initial_nll <- as.numeric(nll)
          initial_gr <- as.numeric(gradient)
        }
      }
      mark("evaluate")
      if (record) {
        result$initial_objective <- initial_nll
        result$initial_gradient <- initial_gr
        result$final_objective <- as.numeric(nll)
        result$final_gradient <- as.numeric(gradient)
        result$final_parameters <- as.numeric(obj$env$last.par.best)
        result$function_evaluations <- n_eval
        result$gradient_evaluations <- n_eval
      }
    }

    if (target >= 4L) {
      opt <- nlminb( obj$par, obj$fn, obj$gr,
        control = list(eval.max = 10000, iter.max = 10000, trace = 0)
      )
      mark("optimize")
      if (record) { 
        result$final_parameters <- as.numeric(obj$env$last.par.best)
        result$final_objective <- as.numeric(opt$objective)
        result$final_gradient <- as.numeric(gr(opt$par))
        result$convergence <- opt$convergence
        result$message <- opt$message
        result$iterations <- opt$iterations
        result$function_evaluations <- unname(opt$evaluations[["function"]])
        result$gradient_evaluations <- unname(opt$evaluations[["gradient"]])
      }
    }

    if (target >= 5L) {
      sdr <- TMB::sdreport(obj)
      mark("sdreport")
      if (record) {
        result$sdr_fixed <- summary(sdr, "fixed")
        result$random <- summary(sdr, "random")
        result$report <- summary(sdr, "report")
      }
    }


    switch(teardown,
      clear   = { FIMS::clear(); mark("teardown") },
      release = { obj <- NULL; init_parms <- NULL; gc(); mark("teardown") },
      none    = invisible(NULL)
    )
  }

  structure(
    list(result = result,
         phases = diff(marks),
         stage = stage,
         backend = backend,
         teardown = teardown),
    class = "fims_stage_result"
  )
}



# ---------------------------------------------------------------------------
# Equivalence check for bench::mark(check = fims_check)
# ---------------------------------------------------------------------------

#' Do two runs of the same stage agree?
#'
#' Passed to bench::mark(check = fims_check), which compares one iteration with
#' the next. Only the fields the rung actually produced are compared: a field
#' missing from both is agreement, and missing from one is not. The comparison
#' is numeric, so it works whether a field is a list (initialize_fims()
#' parameters), a named vector (parList()), or a matrix (an sdreport summary).
fims_check <- function(a, b) {
  fa <- a$result
  fb <- b$result
  same <- function(name, tolerance) {
    x <- fa[[name]]
    y <- fb[[name]]
    if (is.null(x) && is.null(y)) return(TRUE)
    if (is.null(x) || is.null(y)) return(FALSE)
    isTRUE(all.equal(unname(unlist(x)), unname(unlist(y)), tolerance = tolerance))
  }
  identical(fa$backend, fb$backend) &&
    same("n_par", 0) && same("n_fixed", 0) && same("n_random", 0) &&
    same("initial_parameters", 1e-10) &&
    same("initial_objective", 1e-8) &&
    same("final_objective", 1e-8) &&
    same("final_parameters", 1e-6) &&
    same("final_gradient", 1e-6) &&
    same("sdr_fixed", 1e-6)
}

# ---------------------------------------------------------------------------
# Installation
# ---------------------------------------------------------------------------

#' Install one FIMS ref from source
#'
#' The compiler flags come from the environment, not from this function:
#' run_fims_benchmark() writes a Makevars per build type and points
#' R_MAKEVARS_USER at it, so the same call produces the -O1 build for Valgrind
#' and the -O2 build for perf. R_LIBS_USER decides which library it lands in, so
#' both builds of both refs can coexist.
#'
#' `--preclean` runs `make clean` in the package source before building. It is a
#' no-op when remotes downloads a fresh copy, but it is what stops a local
#' checkout from linking object files left over from a build with different
#' flags -- which would silently mix -O1 and -O2 objects in one library.
#'
#' @param ref Branch name, tag, or commit hash (e.g. "main", "xptr-refactor").
install_fims <- function(ref = "main") {
  message(sprintf("Installing NOAA-FIMS/FIMS@%s ...", ref))

  if (!requireNamespace("remotes", quietly = TRUE)) {
    install.packages("remotes")
  }

  target <- .libPaths()[[1]]

  # A stale 00LOCK-<pkg> left by an interrupted install (a crash, or the OOM
  # killer) makes every later install fail with "failed to lock directory".
  # Clearing it is safe here because the target is this run's own library.
  for (lock in list.files(target, pattern = "^00LOCK", full.names = TRUE)) {
    message("Removing stale lock ", basename(lock))
    unlink(lock, recursive = TRUE)
  }

  remotes::install_github(
    repo = "NOAA-FIMS/FIMS",
    ref = ref,
    force = TRUE,
    build_vignettes = FALSE,
    INSTALL_opts = c("--no-multiarch", "--preclean")
  )

  # install.packages() downgrades a failed install to a warning, so this
  # process would otherwise exit 0 with nothing installed.
  version <- tryCatch(
    as.character(utils::packageVersion("FIMS", lib.loc = target)),
    error = function(e) NA_character_
  )
  if (is.na(version)) {
    stop("Installing FIMS@", ref, " into ", target,
         " did not produce an installed package; see the log above.",
         call. = FALSE)
  }
  message("Installed FIMS ", version, " into ", target)
  invisible(version)
}



