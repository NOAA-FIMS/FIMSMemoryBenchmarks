args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 6L || length(args) %% 2L != 0L) {
  stop(
    "Expected OUTPUT MEMORY CPU VALIDATION followed by REF RESULT pairs.",
    call. = FALSE
  )
}

output <- args[[1L]]
memory_report <- args[[2L]]
cpu_report <- args[[3L]]
validation_report <- args[[4L]]
pairs <- matrix(args[-seq_len(4L)], ncol = 2L, byrow = TRUE)
results <- lapply(seq_len(nrow(pairs)), function(index) {
  result <- readRDS(pairs[index, 2L])
  result$ref <- pairs[index, 1L]
  result
})

escape <- function(value) {
  gsub("|", "\\|", as.character(value), fixed = TRUE)
}

format_number <- function(value) {
  format(value, digits = 10L, scientific = TRUE, trim = TRUE)
}

embed_report <- function(title, path) {
  content <- readLines(path, warn = FALSE)
  if (length(content) && grepl("^# ", content[[1L]])) {
    content <- content[-1L]
  }
  headings <- grepl("^#+ ", content)
  content[headings] <- paste0("#", content[headings])
  c(
    paste0("## ", title), "",
    paste0("Source report: [", basename(path), "](", basename(path), ")"),
    "", content, ""
  )
}

first <- results[[1L]]
model_years <- if (identical(first$model_size, "large")) 120L else 30L
data_rows <- if (identical(first$model_size, "large")) 10368L else 2808L
random_years <- paste0("2 through ", model_years)
lines <- c(
  "# FIMS Benchmark Final Report", "",
  paste0("Generated: `", format(Sys.time(), tz = "UTC", usetz = TRUE), "`"),
  "", "## Model", "",
  sprintf(
    "The benchmark uses the `%s` wrapper-built catch-at-age model with %d years, 12 ages, two fleets, and %s input rows.",
    first$model_size, model_years, format(data_rows, big.mark = ",")
  ),
  "",
  sprintf(
    "It contains %d fixed effects and %d annual recruitment-deviation (`log_devs`) random effects, one for each year from %s.",
    first$n_fixed, first$n_random, random_years
  ),
  "",
  "Observed components include fishing catch, survey index, age compositions, length compositions, weight at age, and age-to-length conversion. Validation compares starting parameters across refs using the same joint objective and `nlminb` controls.",
  "", "## Estimated parameters", ""
)

parameter_count <- length(first$canonical_final_parameters)
comparable <- all(vapply(
  results,
  function(result) {
    setequal(
      result$canonical_parameter_names, first$canonical_parameter_names
    )
  },
  logical(1)
))
if (comparable) {
  aligned_estimates <- lapply(results, function(result) {
    result$canonical_final_parameters[match(
      first$canonical_parameter_names, result$canonical_parameter_names
    )]
  })
  header <- c("| # | Type | Parameter |", paste0(" `", escape(pairs[, 1L]), "` |"))
  lines <- c(
    lines,
    paste(header, collapse = ""),
    paste(c("|---:|---|---|", rep("---:|", nrow(pairs))), collapse = "")
  )
  for (index in seq_len(parameter_count)) {
    estimates <- vapply(
      aligned_estimates,
      function(estimates) format_number(estimates[[index]]),
      character(1)
    )
    lines <- c(lines, paste0(
      "| ", index, " | ", first$parameter_types[[index]], " | `",
      escape(first$canonical_parameter_names[[index]]), "` | ",
      paste(estimates, collapse = " | "), " |"
    ))
  }
} else {
  lines <- c(lines, "Parameter vectors have different lengths and cannot be tabulated side by side.")
}

lines <- c(
  lines, "",
  embed_report("Joint objective validation", validation_report),
  embed_report("CPU profile", cpu_report),
  embed_report("Memory profile", memory_report)
)
leak_report <- file.path(dirname(output), "leak_report.md")
if (file.exists(leak_report)) {
  lines <- c(lines, embed_report("Leak detection", leak_report))
}
while (length(lines) && identical(tail(lines, 1L), "")) {
  lines <- head(lines, -1L)
}
writeLines(lines, output)
cat("Combined final report written to", output, "\n")
