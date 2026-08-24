args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 3L || length(args) %% 2L != 1L) {
  stop("Expected OUTPUT followed by REF RESULT pairs.", call. = FALSE)
}

output <- args[[1L]]
pairs <- matrix(args[-1L], ncol = 2L, byrow = TRUE)
results <- lapply(seq_len(nrow(pairs)), function(index) {
  result <- readRDS(pairs[index, 2L])
  result$ref <- pairs[index, 1L]
  result
})

format_number <- function(value) {
  if (length(value) == 0L || is.na(value)) "—" else format(value, digits = 8L)
}

lines <- c(
  "# FIMS Joint Objective Validation", "",
  "Both branches use the same wrapper-built model, starting values, joint fixed/random objective, and `nlminb` controls.", "",
  "## Optimization summary", "",
  "| Git ref | Backend | Fixed | Random | Initial objective | Final objective | Final gradient norm | Convergence | Iterations | Function evals | Gradient evals | Elapsed |",
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
  comparable <- length(first$initial_parameters) == length(second$initial_parameters)
  value <- function(expression) if (comparable) expression else NA_real_
  metrics <- c(
    "Initial objective absolute difference" = value(abs(first$initial_objective - second$initial_objective)),
    "Initial gradient maximum absolute difference" = value(max(abs(first$initial_gradient - second$initial_gradient))),
    "Final objective absolute difference" = value(abs(first$final_objective - second$final_objective)),
    "Final parameters maximum absolute difference" = value(max(abs(first$final_parameters - second$final_parameters))),
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
    sprintf("Parameter dimensions agree: **%s**. Convergence codes agree: **%s**.",
            if (comparable) "yes" else "no",
            if (identical(first$convergence, second$convergence)) "yes" else "no")
  )
}

writeLines(lines, output)
cat("Joint validation report written to", output, "\n")
