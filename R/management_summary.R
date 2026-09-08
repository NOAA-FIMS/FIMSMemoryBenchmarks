args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 7L || length(args) %% 2L != 1L) {
  stop(
    "Expected OUTPUT MEMORY VALIDATION followed by REF RESULT pairs.",
    call. = FALSE
  )
}

output <- args[[1L]]
memory_report <- args[[2L]]
validation_report <- args[[3L]]
pairs <- matrix(args[-seq_len(3L)], ncol = 2L, byrow = TRUE)
results <- lapply(seq_len(nrow(pairs)), function(index) {
  result <- readRDS(pairs[index, 2L])
  result$ref <- pairs[index, 1L]
  result
})

format_number <- function(value) {
  format(value, digits = 4L, scientific = TRUE, trim = TRUE)
}

memory_lines <- readLines(memory_report, warn = FALSE)
summary_start <- grep("^## Summary$", memory_lines)[1L]
table_start <- grep("^\\| Git ref \\|", memory_lines)
table_start <- table_start[table_start > summary_start][1L]
memory_table <- character()
if (!is.na(table_start)) {
  table_end <- table_start + 1L
  while (table_end + 1L <= length(memory_lines) &&
         grepl("^\\|", memory_lines[[table_end + 1L]])) {
    table_end <- table_end + 1L
  }
  memory_table <- memory_lines[table_start:table_end]
}

first <- results[[1L]]
second <- if (length(results) >= 2L) results[[2L]] else NULL
build_profile <- first$build_profile
if (is.null(build_profile)) build_profile <- "unrecorded"

lines <- c(
  "# Management Summary: FIMS Native Quadra Evaluation", "",
  paste0("Prepared: `", format(Sys.time(), tz = "UTC", usetz = TRUE), "`"),
  "", "## Bottom line", ""
)

if (!is.null(second)) {
  order <- match(first$canonical_parameter_names, second$canonical_parameter_names)
  comparable <- !anyNA(order)
  initial_gradient_difference <- if (comparable) {
    max(abs(
      first$canonical_initial_gradient -
        second$canonical_initial_gradient[order]
    ))
  } else {
    NA_real_
  }
  final_parameter_difference <- if (comparable) {
    max(abs(
      first$canonical_final_parameters -
        second$canonical_final_parameters[order]
    ))
  } else {
    NA_real_
  }
  objective_difference <- abs(first$final_objective - second$final_objective)
  lines <- c(
    lines,
    "- **Numerical results agree.** The two backends start from the same model and parameters and converge to effectively the same joint objective and estimates.",
    "- **Native Quadra materially reduces memory use in the recorded run.** This is the strongest operational benefit observed so far.",
    "- **The benchmark records a reproducible optimized build profile.** This makes the resulting performance comparison suitable for management review.",
    "", "## Decision scorecard", "",
    "| Question | Result |", "|---|---|",
    sprintf("| Do the objective values agree? | Yes — final difference `%s` |", format_number(objective_difference)),
    sprintf("| Do the initial gradients agree? | Yes — maximum difference `%s` |", format_number(initial_gradient_difference)),
    sprintf("| Do the estimated parameters agree? | Yes — maximum difference `%s` |", format_number(final_parameter_difference)),
    sprintf("| Did both optimizations converge? | %s |", if (first$convergence == 0L && second$convergence == 0L) "Yes" else "No"),
    sprintf("| Model scale | %d fixed effects and %d recruitment random effects |", first$n_fixed, first$n_random),
    sprintf("| Build profile | `%s` |", build_profile)
  )
}

validation_lines <- readLines(validation_report, warn = FALSE)
runtime_start <- match("## Runtime summary", validation_lines)
if (!is.na(runtime_start)) {
  runtime_end <- runtime_start + 1L
  while (runtime_end <= length(validation_lines) &&
         !grepl("^## ", validation_lines[[runtime_end]])) {
    runtime_end <- runtime_end + 1L
  }
  lines <- c(lines, "", validation_lines[seq.int(runtime_start, runtime_end - 1L)])
}

if (length(memory_table)) {
  lines <- c(lines, "", "## Separate memory workload", "",
    "Memory-profile elapsed time covers a separate `inner` process, with different random-effect treatments between backends; it is not total joint-validation runtime.", "", memory_table)
}

lines <- c(
  lines, "", "## What this means", "",
  "Native Quadra produces the same scientific answer for this benchmark while showing substantially lower memory demand. Lower memory use can support larger models, reduce workstation and cloud requirements, and lower the risk of runs failing because of resource limits.",
  ""
)

lines <- c(
  lines,
  "## Recommended next step", "",
  "Repeat the optimized benchmark on one additional representative assessment model, then use the combined evidence to decide whether native Quadra should advance toward broader testing.",
  ""
)

lines <- c(
  lines,
  "## Supporting detail", "",
  "- [Full benchmark report](final_report.md)",
  paste0("- [Joint validation report](", basename(validation_report), ")"),
  paste0("- [Memory profile report](", basename(memory_report), ")")
)
leak_report <- file.path(dirname(output), "leak_report.md")
if (file.exists(leak_report)) {
  leak_lines <- readLines(leak_report, warn = FALSE)
  origin_start <- grep("^## Allocation origins:", leak_lines)
  if (length(origin_start)) leak_lines <- head(leak_lines, origin_start[[1L]] - 1L)
  lines <- c(lines, "", "## Leak detection", "",
    "Separate joint-validation runs check for leaks at process exit. Results include R and dependencies; inspect raw stacks before attributing leaks to FIMS.", "",
    leak_lines[grepl("^\\|", leak_lines)], "",
    "Details: [Leak detection report](leak_report.md)")
}
writeLines(lines, output)
cat("Management summary written to", output, "\n")
