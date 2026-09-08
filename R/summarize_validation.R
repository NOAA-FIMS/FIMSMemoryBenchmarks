args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 3L || length(args) %% 2L != 1L) {
  stop("Expected OUTPUT followed by REF RESULT pairs.", call. = FALSE)
}

output <- args[[1L]]
pairs <- matrix(args[-1L], ncol = 2L, byrow = TRUE)
results <- lapply(seq_len(nrow(pairs)), function(index) {
  result <- readRDS(pairs[index, 2L])
  result$ref <- pairs[index, 1L]
  runtime_path <- paste0(pairs[index, 2L], ".runtime_seconds")
  result$total_runtime_seconds <- if (file.exists(runtime_path)) {
    value <- scan(runtime_path, quiet = TRUE)
    if (length(value) != 1L || !is.finite(value) || value < 0) {
      stop("Invalid total runtime: ", runtime_path, call. = FALSE)
    }
    value
  } else NA_real_
  result
})

format_number <- function(value) {
  if (length(value) == 0L || is.na(value)) "—" else format(value, digits = 8L)
}

lines <- c(
  "# FIMS Joint Objective Validation", "",
  "Both branches use the same wrapper-built model, starting values, joint fixed/random objective, and `nlminb` controls.", "",
  "## Runtime summary", "",
  "Total runtime is wall-clock time from launching the validation R process until it exits, including startup, package loading, model and tape construction, initial evaluation, joint optimization, final evaluation, and saving results. It excludes branch installation and separate memory/CPU profiling runs. Optimization time measures only `nlminb`. Both branches use the joint objective for these timings. Historical runs without a timing record show 'Not recorded'; total runtime cannot be reconstructed by adding timings from separate runs.", "",
  "| Git ref | Total runtime | Optimization only |",
  "|---|---:|---:|"
)
for (result in results) {
  total <- if (is.na(result$total_runtime_seconds)) "Not recorded" else sprintf("%.3f s", result$total_runtime_seconds)
  lines <- c(lines, sprintf("| %s | %s | %.3f s |", result$ref, total, result$elapsed_seconds))
}
lines <- c(lines, "",
  "## Optimization summary", "",
  "| Git ref | Backend | Fixed | Random | Initial objective | Final objective | Final gradient norm | Convergence | Iterations | Function evals | Gradient evals | Optimization elapsed |",
  "|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|"
)
for (result in results) {
  lines <- c(lines, sprintf(
    "| %s | %s | %d | %d | %s | %s | %s | %d | %d | %d | %d | %.3fs |",
    result$ref, result$backend, result$n_fixed, result$n_random,
    format_number(result$initial_objective),
    format_number(result$final_objective),
    format_number(sqrt(sum(result$final_gradient^2))),
    result$convergence, result$iterations, result$function_evaluations,
    result$gradient_evaluations, result$elapsed_seconds
  ))
}

if (length(results) == 2L) {
  first <- results[[1L]]
  second <- results[[2L]]
  second_order <- match(
    first$canonical_parameter_names, second$canonical_parameter_names
  )
  comparable <- !anyNA(second_order) &&
    length(second_order) == length(second$canonical_parameter_names)
  value <- function(expression) if (comparable) expression else NA_real_
  metrics <- c(
    "Initial objective absolute difference" = value(abs(first$initial_objective - second$initial_objective)),
    "Initial parameters maximum absolute difference" = value(max(abs(first$canonical_initial_parameters - second$canonical_initial_parameters[second_order]))),
    "Initial gradient maximum absolute difference" = value(max(abs(first$canonical_initial_gradient - second$canonical_initial_gradient[second_order]))),
    "Final objective absolute difference" = value(abs(first$final_objective - second$final_objective)),
    "Final parameters maximum absolute difference" = value(max(abs(first$canonical_final_parameters - second$canonical_final_parameters[second_order]))),
    "Final gradient maximum absolute difference" = value(max(abs(first$canonical_final_gradient - second$canonical_final_gradient[second_order]))),
    "Iteration count difference" = abs(first$iterations - second$iterations),
    "Function evaluation count difference" = abs(first$function_evaluations - second$function_evaluations),
    "Gradient evaluation count difference" = abs(first$gradient_evaluations - second$gradient_evaluations)
  )
  lines <- c(lines, "", "## Agreement", "", "| Metric | Difference |", "|---|---:|")
  for (name in names(metrics)) {
    lines <- c(lines, sprintf("| %s | %s |", name, format_number(metrics[[name]])))
  }
  lines <- c(
    lines, "",
    "Parameter and gradient differences are calculated after aligning logical parameter names and converting `log_slope` to the natural slope scale.",
    "",
    sprintf("Canonical parameter sets agree: **%s**. Convergence codes agree: **%s**.",
            if (comparable) "yes" else "no",
            if (identical(first$convergence, second$convergence)) "yes" else "no")
  )
}

writeLines(lines, output)
cat("Joint validation report written to", output, "\n")
