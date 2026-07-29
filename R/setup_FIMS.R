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


setup_fims_model <- function(mode = c("helper", "sd_report_clear", "sd_report",
                                      "opt_only", "inner", "tape_only",
                                      "initialize_only")) {
  mode <- match.arg(mode)

  # Map modes to execution depths
  mode_levels <- c(
    "initialize_only" = 1,
    "tape_only"       = 2,
    "inner"           = 3,
    "opt_only"        = 4,
    "sdreport"        = 5,
    "sdreport_clear"  = 6,
    "helper"          = 7
  )

  library(FIMS)
  clear()

  target_level <- mode_levels[[mode]]

  # Step 1: Initialize (Always runs)
  message("--> Step 1: Initializing data & parameters...")

  data("data_big")
  # Prepare the package data for being used in a FIMS model
  data_4_model <- FIMSFrame(data_big)

  parameters_4_model <- create_default_configurations(data = data_4_model) |>
    create_default_parameters(data = data_4_model) |>
    tidyr::unnest(cols = data) |>
    # Update log_Fmort initial values for Fleet1
    dplyr::rows_update(
      tibble::tibble(
        fleet = "fleet1",
        label = "log_Fmort",
        time = seq(get_n_years(data_4_model)),
        value = log(c(
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
        ))
      ),
      by = c("fleet", "label", "time")
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
      tibble::tibble(
        label = "log_devs",
        time = 2:get_n_years(data_4_model),
        value = c(
          0.43787763, -0.13299042, -0.43251973, 0.64861200, 0.50640852,
          -0.06958319, 0.30246260, -0.08257384, 0.20740372, 0.15289604,
          -0.21709207, -0.13320626, 0.11225374, -0.10650836, 0.26877132,
          0.24094126, -0.54480751, -0.23680557, -0.58483386, 0.30122785,
          0.21930545, -0.22281699, -0.51358369, 0.15740234, -0.53988240,
          -0.19556523, 0.20094360, 0.37248740, -0.07163145
        )
      ),
      by = c("label", "time")
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

  if (target_level == 1) return()

  if (target_level == 7) {
    fit <- init_parms |>
      fit_fims(optimize = TRUE)
    clear()
    return()
  }

  # obj <- TMB::MakeADFun(
  #   data = list(),
  #   parameters = init_parameters,
  #   random = "re",
  #   DLL = "FIMS",
  #   silent = TRUE
  # )

  if (target_level == 2) return()

  if (target_level == 3) {
    obj$fn()
    obj$gr()
    return()
  }

  # opt <- nlminb(
  #   start = obj$par,
  #   objective = obj$fn,
  #   gradient = obj$gr,
  #   control = list(eval.max = 10000, iter.max = 10000, trace = 0)
  # )
  if (target_level == 4) return()

  # sdreport <- TMB::sdreport(obj)
  if (target_level == 5) return()

  clear()
  if (target_level == 6) return()

}
