#' Install a specific FIMS branch compiled in Debug Mode
#'
#' @param ref Branch name, tag, or commit hash (e.g. "main", "xptr-refactor")
install_fims_debug <- function(ref = "main") {
  message(sprintf("Installing NOAA-FIMS/FIMS@%s in debug mode...", ref))

  # Ensure remotes is available
  if (!requireNamespace("remotes", quietly = TRUE)) {
    install.packages("remotes")
  }

  # Force compilation from source with user's ~/.R/Makevars applied
  remotes::install_github(
    repo = "NOAA-FIMS/FIMS",
    ref = ref,
    force = TRUE,
    build_vignettes = FALSE,
    INSTALL_opts = c("--no-multiarch")
  )
}

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


setup_fims_model <- function(mode = c(
                               "helper", "sd_report_clear", "sd_report",
                               "opt_only", "inner", "tape_only",
                               "initialize_only", "validation"
                             ),
                             inner_duration_seconds = 0,
                             model_size = Sys.getenv(
                               "FIMS_BENCHMARK_MODEL_SIZE", "large"
                             )) {
  mode <- match.arg(mode)
  model_size <- match.arg(model_size, c("medium", "large"))
  if (!is.numeric(inner_duration_seconds) ||
      length(inner_duration_seconds) != 1L ||
      is.na(inner_duration_seconds) ||
      inner_duration_seconds < 0) {
    stop("`inner_duration_seconds` must be one non-negative number.",
         call. = FALSE)
  }

  # Map modes to execution depths
  mode_levels <- c(
    "initialize_only" = 1,
    "tape_only"       = 2,
    "inner"           = 3,
    "opt_only"        = 4,
    "sd_report"       = 5,
    "sd_report_clear" = 6,
    "helper"          = 7,
    "validation"      = 8
  )

  library(FIMS)
  clear()

  target_level <- mode_levels[[mode]]

  message("--> Step 1: Initializing data & parameters...")

  data("data_big")
  model_years <- if (model_size == "large") 120L else 30L
  benchmark_data <- if (model_size == "large") {
    expand_fims_years(data_big, model_years)
  } else {
    data_big
  }
  message(sprintf(
    "--> Model size: %s (%d years)", model_size, model_years
  ))
  # Prepare the package data for being used in a FIMS model
  data_4_model <- FIMSFrame(benchmark_data)

  if (exists("setup_default_parameters", mode = "function")) {
    parameters_4_model <- setup_default_parameters(data = data_4_model)
    timing_column <- "timing"
  } else {
    parameters_4_model <- create_default_configurations(data = data_4_model) |>
      create_default_parameters(data = data_4_model) |>
      tidyr::unnest(cols = data)
    timing_column <- "time"
  }

  fishing_mortality <- tibble::tibble(
    fleet = "fleet1",
    label = "log_Fmort",
    value = log(rep(c(
      0.009459165, 0.027288858, 0.045063639,
      0.061017825, 0.048600752, 0.087420554,
      0.088447204, 0.186607929, 0.109008958,
      0.132704335, 0.150615473, 0.161242955,
      0.116640187, 0.169346119, 0.180191913,
      0.161240483, 0.314573212, 0.257247574,
      0.254887252, 0.251462108, 0.349101406,
      0.254107720, 0.418478117, 0.345721184,
      0.343685540, 0.314171227, 0.308026829,
      0.431745298, 0.328030899, 0.499675368
    ), length.out = model_years))
  )
  fishing_mortality[[timing_column]] <- seq(get_n_years(data_4_model))

  recruitment_deviations <- tibble::tibble(
    label = "log_devs",
    value = rep(c(
      0.43787763, -0.13299042, -0.43251973, 0.64861200, 0.50640852,
      -0.06958319, 0.30246260, -0.08257384, 0.20740372, 0.15289604,
      -0.21709207, -0.13320626, 0.11225374, -0.10650836, 0.26877132,
      0.24094126, -0.54480751, -0.23680557, -0.58483386, 0.30122785,
      0.21930545, -0.22281699, -0.51358369, 0.15740234, -0.53988240,
      -0.19556523, 0.20094360, 0.37248740, -0.07163145
    ), length.out = model_years - 1L)
  )
  recruitment_deviations[[timing_column]] <- 2:get_n_years(data_4_model)

  parameters_4_model <- parameters_4_model |>
    # Update log_Fmort initial values for Fleet1
    dplyr::rows_update(
      fishing_mortality,
      by = c("fleet", "label", timing_column)
    ) |>
    # Update selectivity parameters and log_q for survey1
    dplyr::rows_update(
      tibble::tibble(
        fleet = "survey1",
        label = c("inflection_point", "slope", "log_q"),
        value = c(1.5, 2, log(3.315143e-07))
      ),
      by = c("fleet", "label")
    ) |>
    # Update log_devs in the Recruitment module (time steps 2-30)
    dplyr::rows_update(
      recruitment_deviations,
      by = c("label", timing_column)
    ) |>
    # Update log_sd for log_devs in the Recruitment module
    dplyr::rows_update(
      tibble::tibble(
        module_name = "Recruitment",
        label = "log_sd",
        value = 0.4
      ),
      by = c("module_name", "label")
    ) |>
    # Update inflection point and slope parameters in the Maturity module
    dplyr::rows_update(
      tibble::tibble(
        module_name = "Maturity",
        label = c("inflection_point", "slope"),
        value = c(2.25, 3)
      ),
      by = c("module_name", "label")
    ) |>
    # Update log_init_naa values in the Population module
    dplyr::rows_update(
      tibble::tibble(
        label = "log_init_naa",
        age = seq(get_n_ages(data_4_model)),
        value = c(
          13.80944, 13.60690, 13.40217, 13.19525, 12.98692, 12.77791,
          12.56862, 12.35922, 12.14979, 11.94034, 11.73088, 13.18755
        )
      ),
      by = c("label", "age")
    )

  init_parms <- parameters_4_model |>
    initialize_fims(data = data_4_model)

  if (target_level == 1) {
    return(print("model ran without error"))
  }

  if (target_level == 7) {
    message("--> Step 2: Fit model with fit_fims helper function...")
    fit <- init_parms |>
      fit_fims(optimize = TRUE)
    clear()
    return(print("model ran without error"))
  }

  fims_namespace <- asNamespace("FIMS")
  native_quadra_evaluate <- get0(
    "native_quadra_evaluate",
    envir = fims_namespace,
    mode = "function",
    inherits = FALSE
  )
  native_quadra_fit <- get0(
    "native_quadra_fit",
    envir = fims_namespace,
    mode = "function",
    inherits = FALSE
  )
  native_quadra_sdreport <- get0(
    "native_quadra_sdreport",
    envir = fims_namespace,
    mode = "function",
    inherits = FALSE
  )
  has_native_quadra <- all(vapply(
    list(native_quadra_evaluate, native_quadra_fit, native_quadra_sdreport),
    is.function,
    logical(1)
  ))

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
  has_legacy_quadra <- !has_native_quadra && has_legacy_quadra_api && tryCatch(
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
  quadra_backend <- if (has_native_quadra) {
    "native"
  } else if (has_legacy_quadra) {
    "legacy"
  } else {
    "none"
  }

  if (target_level == 8) {
    fixed <- get_fixed()
    random <- get_random()
    start <- c(fixed, random)
    if (quadra_backend == "native") {
      evaluate <- function(parameters) {
        native_quadra_evaluate(
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
    objective <- function(parameters) evaluate(parameters)$objective
    gradient <- function(parameters) evaluate(parameters)$gradient
    started <- proc.time()[["elapsed"]]
    fit <- nlminb(
      start = start,
      objective = objective,
      gradient = gradient,
      control = list(eval.max = 2000, iter.max = 1000, trace = 0)
    )
    elapsed <- proc.time()[["elapsed"]] - started
    final <- evaluate(fit$par)
    return(list(
      backend = if (quadra_backend == "none") "TMB" else quadra_backend,
      model_size = model_size,
      n_fixed = length(fixed),
      n_random = length(random),
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

  if (quadra_backend == "native") {
    message("--> Step 2: Use native Quadra model...")
  } else if (quadra_backend == "legacy") {
    message("--> Step 2: Created legacy Quadra model...")
  } else {
    message("--> Step 2: Create TMB tape...")

    obj <- TMB::MakeADFun(
      data = list(),
      parameters = init_parms$parameters,
      random = "re",
      DLL = "FIMS",
      silent = TRUE
    )
  }



  if (target_level == 2) {
    return(print("model ran without error"))
  }

  if (target_level == 3) {
    message("--> Step 3: Evaluate objective and gradient...")
    evaluate_inner <- if (quadra_backend == "native") {
      fixed <- get_fixed()
      random <- get_random()
      function() native_quadra_evaluate(fixed = fixed, random = random)
    } else if (quadra_backend == "legacy") {
      fixed <- get_fixed()
      random <- get_random()
      function() EvaluateQuadraModel(
        fixed_values = fixed,
        random_values = random
      )
    } else {
      function() {
        obj$fn()
        obj$gr()
      }
    }
    started <- proc.time()[["elapsed"]]
    evaluations <- 0L
    repeat {
      evaluate_inner()
      evaluations <- evaluations + 1L
      if (inner_duration_seconds == 0 ||
          proc.time()[["elapsed"]] - started >= inner_duration_seconds) {
        break
      }
    }
    message(sprintf("--> Completed %d inner evaluation(s).", evaluations))
    return(print("model ran without error"))
  }

  message("--> Step 4: Fit the model...")
  if (quadra_backend == "native") {
    fit <- native_quadra_fit(
      fixed = get_fixed(),
      random = get_random(),
      method = "joint",
      max_iterations = 500L,
      gradient_tolerance = 1e-5
    )
  } else if (quadra_backend == "legacy") {
    fixed0 <- get_fixed()
    random0 <- get_random()
    fit <- fit_fims_quadra_joint(
      fixed_values = fixed0,
      random_values = random0,
      max_iterations = 500L,
      gradient_tolerance = 1e-5
    )
  } else {
    opt <- nlminb(
      start = obj$par,
      objective = obj$fn,
      gradient = obj$gr,
      control = list(eval.max = 10000, iter.max = 10000, trace = 0)
    )
  }

  if (target_level == 4) {
    return(print("model ran without error"))
  }
  if (quadra_backend == "native") {
    message("--> Step 5: Create native Quadra uncertainty report...")
    sdreport <- native_quadra_sdreport(
      fixed = fit$par,
      random = fit$random
    )
  } else if (quadra_backend == "legacy") {
    message("--> Step 5: Create Quadra uncertainty report...")
    if (!exists("quadra_model_diagnostics", mode = "function")) {
      stop(
        "This Quadra build does not expose `quadra_model_diagnostics()`; ",
        "use mode = 'opt_only' or an earlier stage.",
        call. = FALSE
      )
    }
    sdreport <- quadra_model_diagnostics(
      fixed_values = fit$par,
      random_values = fit$random
    )
  } else {
    message("--> Step 5: Call sdreport...")
    sdreport <- TMB::sdreport(obj)
  }
  if (target_level == 5) {
    return(print("model ran without error"))
  }

  message("--> Step 5: clear memory...")
  clear()
  if (target_level == 6) {
    return(print("model ran without error"))
  }
}
