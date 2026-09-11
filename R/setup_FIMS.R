# ---------------------------------------------------------------------------
# Fixture: everything identical across branches. Built once, never timed.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Model size and backend support, ported verbatim from
# feature/macos-instruments-profiling so the upstream reporting keeps working.
# ---------------------------------------------------------------------------

expand_fims_years <- function(data, n_years) {
  base_years <- max(data$timing[data$type == "catch"], na.rm = TRUE)
  static <- data[is.na(data$timing), , drop = FALSE]
  dynamic_types <- unique(data$type[!is.na(data$timing)])
  expanded <- lapply(dynamic_types, function(type) {
    source <- data[data$type == type & !is.na(data$timing), , drop = FALSE]
    source_years <- if (identical(type, "weight_at_age")) {
      base_years + 1L
    } else {
      base_years
    }
    target_years <- if (identical(type, "weight_at_age")) {
      n_years + 1L
    } else {
      n_years
    }
    do.call(rbind, lapply(seq_len(target_years), function(year) {
      source_year <- (year - 1L) %% source_years + 1L
      rows <- source[source$timing == source_year, , drop = FALSE]
      rows$timing <- year
      rows
    }))
  })
  result <- do.call(rbind, c(list(static), expanded))
  rownames(result) <- NULL
  result
}



# Resolve complete modern APIs from FIMS itself, preferring the XPtr API.
resolve_quadra_api <- function(namespace) {
  for (backend in c("xptr", "native")) {
    prefix <- if (backend == "xptr") "quadra_" else "native_quadra_"
    functions <- lapply(paste0(prefix, c("evaluate", "fit", "sdreport")), function(name) {
      get0(name, envir = namespace, mode = "function", inherits = FALSE)
    })
    if (all(vapply(functions, is.function, logical(1)))) {
      names(functions) <- c("evaluate", "fit", "sdreport")
      return(c(list(backend = backend), functions))
    }
  }
  NULL
}



setup_fims_inputs <- function(size = c("normal", "large"), n_years = NULL) {
  size <- match.arg(size)
  if (is.null(n_years)) {
    n_years <- if (identical(size, "large")) 120L else 30L
  }
  n_years <- as.integer(n_years)

  data_big <- NULL
  utils::data("data_big", package = "FIMS", envir = environment())

  # "normal" is data_big as shipped (30 years). Longer models are built by
  # recycling its years, so the model grows in dimension while every value stays
  # one of the tuned ones.
  benchmark_data <- if (n_years > 30L) expand_fims_years(data_big, n_years) else data_big
  message(sprintf("--> Fixture: %s (%d years)", size, n_years))
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
setup_fims_model <- function(fixture,
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
# End-to-end path, kept separate because it does not share the same workflow
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


# ---------------------------------------------------------------------------
# Joint objective validation
# ---------------------------------------------------------------------------

#' Fit the joint objective and return everything needed to compare two builds
#'
#' Ported from setup_fims_model(mode = "validation") on
#' feature/macos-instruments-profiling. The returned list is a contract:
#' R/summarize_validation.R, R/final_report.R and R/management_summary.R all
#' read these names, so add fields rather than renaming them.
#'
#' Dispatches over whichever backend the installed FIMS provides -- the XPtr or
#' native Quadra callbacks when present, TMB otherwise -- so the same comparison
#' works across the branches being benchmarked.
#'
#' @param fixture Output of setup_fims_inputs().
#' @return A list of parameters, objectives, gradients and convergence details.
run_fims_validation <- function(fixture) {
  n_years <- FIMS::get_n_years(fixture$data)
  model_size <- if (!is.null(fixture$size)) fixture$size else if (n_years > 30L) "large" else "normal"

  FIMS::clear()
  init_parms <- FIMS::initialize_fims(fixture$parameters, data = fixture$data)

    fims_namespace <- asNamespace("FIMS")
    quadra_api <- resolve_quadra_api(fims_namespace)
    has_modern_quadra <- !is.null(quadra_api)

    legacy_quadra_functions <- c(
      "CreateQuadraModel", "EvaluateQuadraModel", "fit_fims_quadra_joint",
      "get_fixed", "get_random"
    )
    has_legacy_quadra_api <- all(vapply(
      legacy_quadra_functions,
      exists,
      logical(1),
      mode = "function",
      inherits = TRUE
    ))
    has_legacy_quadra <- !has_modern_quadra && has_legacy_quadra_api && tryCatch(
      {
        CreateQuadraModel()
        TRUE
      },
      error = function(error) {
        if (grepl(
          "Quadra support was not enabled",
          conditionMessage(error),
          fixed = TRUE
        )) {
          return(FALSE)
        }
        stop(error)
      }
    )
    quadra_backend <- if (has_modern_quadra) {
      quadra_api$backend
    } else if (has_legacy_quadra) {
      "legacy"
    } else {
      "none"
    }

      fixed <- get_fixed()
      random <- get_random()
      start <- c(fixed, random)
      fixed_name_function <- get0(
        "native_get_parameter_names",
        envir = fims_namespace,
        mode = "function", inherits = FALSE
      )
      fixed_names <- if (is.function(fixed_name_function)) {
        fixed_name_function()
      } else {
        named_fixed <- get0(
          "get_parameter_names",
          envir = fims_namespace,
          mode = "function", inherits = FALSE
        )(fixed)
        names(named_fixed)
      }
      random_name_function <- get0(
        "get_random_names",
        envir = fims_namespace,
        mode = "function", inherits = FALSE
      )
      random_names <- names(random_name_function(random))
      if (length(fixed_names) != length(fixed)) {
        fixed_names <- paste0("fixed_effect_", seq_along(fixed))
      }
      if (length(random_names) != length(random)) {
        random_names <- paste0("random_effect_", seq_along(random))
      }
      if (length(random) == n_years - 1L &&
        all(grepl("^random_effect_", random_names))) {
        random_names <- paste0(
          "Recruitment.1.log_devs.", seq.int(2L, n_years)
        )
      }
      if (quadra_backend %in% c("xptr", "native")) {
        evaluate <- function(parameters) {
          quadra_api$evaluate(
            fixed = parameters[seq_along(fixed)],
            random = parameters[length(fixed) + seq_along(random)]
          )
        }
      } else if (quadra_backend == "legacy") {
        evaluate <- function(parameters) {
          EvaluateQuadraModel(
            fixed_values = parameters[seq_along(fixed)],
            random_values = parameters[length(fixed) + seq_along(random)]
          )
        }
      } else {
        joint <- TMB::MakeADFun(
          data = list(),
          parameters = init_parms$parameters,
          DLL = "FIMS",
          silent = TRUE
        )
        evaluate <- function(parameters) {
          list(
            objective = joint$fn(parameters),
            gradient = joint$gr(parameters)
          )
        }
      }
      initial <- evaluate(start)
      split_prefix <- if (quadra_backend == "native") "native_quadra_" else "quadra_"
      split_objective <- get0(paste0(split_prefix, "objective"), fims_namespace, mode = "function", inherits = FALSE)
      split_gradient <- get0(paste0(split_prefix, "gradient"), fims_namespace, mode = "function", inherits = FALSE)
      if (quadra_backend %in% c("xptr", "native") && is.function(split_objective) && is.function(split_gradient)) {
        objective <- function(parameters) split_objective(
          fixed = parameters[seq_along(fixed)],
          random = parameters[length(fixed) + seq_along(random)]
        )
        gradient <- function(parameters) split_gradient(
          fixed = parameters[seq_along(fixed)],
          random = parameters[length(fixed) + seq_along(random)]
        )
      } else if (quadra_backend == "none") {
        objective <- joint$fn
        gradient <- joint$gr
      } else {
        objective <- function(parameters) evaluate(parameters)$objective
        gradient <- function(parameters) evaluate(parameters)$gradient
      }
      started <- proc.time()[["elapsed"]]
      fit <- nlminb(
        start = start,
        objective = objective,
        gradient = gradient,
        control = list(eval.max = 2000, iter.max = 1000, trace = 0)
      )
      elapsed <- proc.time()[["elapsed"]] - started
      final <- evaluate(fit$par)
      raw_names <- c(fixed_names, random_names)
      canonical_base <- sub("\\.[0-9]+$", "", raw_names)
      canonical_base <- sub("\\.log_slope$", ".slope", canonical_base)
      canonical_base <- sub(
        "^dnorm\\.[0-9]+\\.log_sd$", "Recruitment.1.log_sd",
        canonical_base
      )
      occurrence <- ave(
        seq_along(canonical_base), canonical_base,
        FUN = function(index) seq_along(index) - 1L
      )
      repeated <- table(canonical_base)[canonical_base] > 1L
      canonical_names <- canonical_base
      canonical_names[repeated] <- paste0(
        canonical_base[repeated], ".", occurrence[repeated]
      )
      log_slope <- grepl("\\.log_slope\\.[0-9]+$", raw_names)
      canonical_initial <- start
      canonical_final <- as.numeric(fit$par)
      canonical_initial[log_slope] <- exp(canonical_initial[log_slope])
      canonical_final[log_slope] <- exp(canonical_final[log_slope])
      canonical_initial_gradient <- as.numeric(initial$gradient)
      canonical_final_gradient <- as.numeric(final$gradient)
      canonical_initial_gradient[log_slope] <-
        canonical_initial_gradient[log_slope] / canonical_initial[log_slope]
      canonical_final_gradient[log_slope] <-
        canonical_final_gradient[log_slope] / canonical_final[log_slope]
      return(list(
        backend = if (quadra_backend == "none") "TMB" else quadra_backend,
        build_profile = Sys.getenv(
          "FIMS_BENCHMARK_BUILD_PROFILE", "unrecorded"
        ),
        model_size = model_size,
        n_fixed = length(fixed),
        n_random = length(random),
        parameter_names = c(fixed_names, random_names),
        parameter_types = c(
          rep("fixed", length(fixed)), rep("random", length(random))
        ),
        canonical_parameter_names = canonical_names,
        canonical_initial_parameters = canonical_initial,
        canonical_initial_gradient = canonical_initial_gradient,
        canonical_final_parameters = canonical_final,
        canonical_final_gradient = canonical_final_gradient,
        initial_parameters = start,
        initial_objective = as.numeric(initial$objective),
        initial_gradient = as.numeric(initial$gradient),
        final_parameters = as.numeric(fit$par),
        final_objective = as.numeric(final$objective),
        final_gradient = as.numeric(final$gradient),
        convergence = fit$convergence,
        message = fit$message,
        iterations = fit$iterations,
        function_evaluations = unname(fit$evaluations[["function"]]),
        gradient_evaluations = unname(fit$evaluations[["gradient"]]),
        elapsed_seconds = unname(elapsed)
      ))
}

