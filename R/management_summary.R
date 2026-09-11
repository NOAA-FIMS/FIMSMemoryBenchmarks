args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 5L || length(args) %% 2L != 1L) {
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
lines <- c(
  "# Management Summary: FIMS Branch Comparison", "",
  paste0("Prepared: `", format(Sys.time(), tz = "UTC", usetz = TRUE), "`"), "",
  paste0("Baseline: `", first$ref, "`. Each other ref is compared with this baseline."), "",
  "## Validation scorecard", "",
  "| Ref | Backend | Final objective difference | Max parameter difference | Convergence code | Build profile |",
  "|---|---|---:|---:|---:|---|"
)
for (result in results) {
  order <- match(first$canonical_parameter_names, result$canonical_parameter_names)
  comparable <- !anyNA(order) && length(order) == length(result$canonical_parameter_names)
  difference <- if (comparable) max(abs(first$canonical_final_parameters - result$canonical_final_parameters[order])) else NA_real_
  build <- if (is.null(result$build_profile)) "unrecorded" else result$build_profile
  lines <- c(lines, sprintf("| %s | %s | %s | %s | %d | %s |",
    result$ref, result$backend,
    format_number(abs(first$final_objective - result$final_objective)),
    format_number(difference), result$convergence, build))
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
  "Assess numerical agreement and convergence for each ref alongside runtime and memory. Different backend treatments in the separate memory workload limit direct interpretation.",
  ""
)

lines <- c(
  lines,
  "## Recommended next step", "",
  "Repeat promising comparisons on representative assessment models before drawing general performance conclusions.",
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
