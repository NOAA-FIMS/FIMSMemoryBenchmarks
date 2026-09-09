# Everything the standard reports leave out, explained in plain language.
#
# The Markdown reports answer "which branch is better". This answers "why", and
# is meant to be readable without knowing anything about Valgrind, perf, or
# Instruments. Every number here comes from the results tables in a run
# directory, so nothing is re-measured.
#
#   Rscript R/additional_report_metrics.R                     # newest run
#   Rscript R/additional_report_metrics.R outputs/2026...     # a specific run
#
# It writes additional_metrics.md into the run directory and prints the same
# tables to the console.

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
})

# ---- locate the run ---------------------------------------------------------

args <- commandArgs(trailingOnly = TRUE)
repo_root <- normalizePath(
  if (requireNamespace("here", quietly = TRUE)) here::here() else getwd(),
  mustWork = TRUE
)

run_dir <- if (length(args) >= 1) {
  args[[1]]
} else {
  runs <- list.dirs(file.path(repo_root, "outputs"), recursive = FALSE)
  runs <- runs[file.exists(file.path(runs, "manifest.tsv")) |
                 lengths(lapply(runs, list.files, pattern = "^results.*[.]tsv$")) > 0]
  if (!length(runs)) {
    stop("No run directories found under outputs/. Run a benchmark first, or pass a path.",
         call. = FALSE)
  }
  runs[[which.max(file.info(runs)$mtime)]]
}

if (!dir.exists(run_dir)) {
  stop("No such run directory: ", run_dir,
       "\nPass a path under outputs/, or no argument at all to use the newest run.",
       call. = FALSE)
}
run_dir <- normalizePath(run_dir, mustWork = TRUE)
result_files <- list.files(run_dir, pattern = "^results.*[.]tsv$", full.names = TRUE)
if (!length(result_files)) {
  stop("No results tables in ", run_dir,
       ". That run produced no measurements; check its *_profile.log files.",
       call. = FALSE)
}

measurements <- bind_rows(lapply(result_files, read.delim,
                                 stringsAsFactors = FALSE, na.strings = "")) |>
  mutate(number = suppressWarnings(as.numeric(value)))

message("Run: ", basename(run_dir))
message("Measurements: ", nrow(measurements), " rows from ",
        paste(basename(result_files), collapse = ", "))

refs <- unique(measurements$ref[!is.na(measurements$ref) & nzchar(measurements$ref)])
baseline_ref <- refs[[1]]

# ---- helpers ----------------------------------------------------------------

# Bytes as a human-readable string; profilers report raw byte counts.
pretty_bytes <- function(x) {
  ifelse(is.na(x), "-", vapply(x, function(value) {
    units <- c("B", "KiB", "MiB", "GiB", "TiB")
    index <- 1L
    while (abs(value) >= 1024 && index < length(units)) {
      value <- value / 1024
      index <- index + 1L
    }
    if (index == 1L) sprintf("%.0f %s", value, units[[index]])
    else sprintf("%.2f %s", value, units[[index]])
  }, character(1)))
}

pretty_seconds <- function(x) {
  ifelse(is.na(x), "-",
         ifelse(x >= 1, sprintf("%.3f s", x),
                ifelse(x >= 1e-3, sprintf("%.2f ms", x * 1e3),
                       sprintf("%.1f us", x * 1e6))))
}

# One row per metric, one column per ref, plus the difference between them.
compare_metrics <- function(data, metrics, format = pretty_bytes) {
  data <- filter(data, metric %in% metrics)
  # dplyr evaluates summarise() expressions even with no groups, so bail out
  # before that rather than warn about min() of nothing.
  if (!nrow(data)) return(NULL)

  wide <- data |>
    group_by(metric, ref) |>
    summarise(value = median(number, na.rm = TRUE), .groups = "drop") |>
    pivot_wider(names_from = ref, values_from = value) |>
    mutate(metric = factor(metric, levels = metrics)) |>
    arrange(metric)

  if (!nrow(wide)) return(NULL)

  if (length(refs) == 2 && all(refs %in% names(wide))) {
    wide <- wide |>
      mutate(
        difference = .data[[refs[[2]]]] - .data[[baseline_ref]],
        percent = ifelse(.data[[baseline_ref]] == 0, NA_real_,
                         difference / .data[[baseline_ref]] * 100)
      )
  }

  formatted <- wide
  for (column in intersect(names(formatted), c(refs, "difference"))) {
    formatted[[column]] <- format(formatted[[column]])
  }
  if ("percent" %in% names(formatted)) {
    formatted$percent <- ifelse(is.na(formatted$percent), "-",
                                sprintf("%+.1f%%", formatted$percent))
  }
  formatted
}

markdown_table <- function(data) {
  if (is.null(data) || !nrow(data)) return(character())
  data[] <- lapply(data, as.character)
  c(paste0("| ", paste(names(data), collapse = " | "), " |"),
    paste0("|", paste(rep("---", ncol(data)), collapse = "|"), "|"),
    apply(data, 1, function(row) paste0("| ", paste(row, collapse = " | "), " |")))
}

section <- function(title, explanation, data) {
  rows <- markdown_table(data)
  if (!length(rows)) return(character())
  c(paste("##", title), "", explanation, "", rows, "")
}

# ---- 1. what the heap was made of -------------------------------------------

heap_breakdown <- measurements |>
  filter(source == "massif", stage != "fixture") |>
  compare_metrics(c("peak_heap", "peak_extra", "peak_stacks", "retained_heap"))

heap_text <- paste(
  "The report shows one peak number. This splits it up. `peak_heap` is memory the",
  "program asked for; `peak_extra` is the allocator's own bookkeeping, which grows",
  "when a program makes many small allocations rather than few large ones;",
  "`peak_stacks` is stack memory, normally zero; `retained_heap` is what was still",
  "held when the process exited. A branch that lowers peak_heap but raises",
  "peak_extra has changed allocation *pattern*, not just size."
)

# ---- 2. how much of the run was measured ------------------------------------

coverage <- measurements |>
  filter(source == "massif", metric %in% c("snapshots", "processes")) |>
  compare_metrics(c("snapshots", "processes"), format = function(x) sprintf("%.0f", x))

coverage_text <- paste(
  "Bookkeeping, not results. `snapshots` is how many times Valgrind sampled memory",
  "during the run: too few means the peak may sit between samples. `processes` is",
  "how many processes were profiled, because R can spawn children; if this is",
  "greater than 1, look at the per-process table in the report."
)

# ---- 3. where the time went outside the model -------------------------------

os_time <- measurements |>
  filter(source == "time") |>
  compare_metrics(c("elapsed_seconds", "user_seconds", "system_seconds"),
                  format = pretty_seconds)

os_time_text <- paste(
  "macOS only. `user` is time spent running the program's own code, `system` is",
  "time spent inside the operating system (allocating memory, reading files), and",
  "`elapsed` is the wall clock. A rise in system time with flat user time usually",
  "means more memory or file activity rather than more computation."
)

paging <- measurements |>
  filter(source == "time") |>
  compare_metrics(c("page_reclaims", "page_faults", "swaps"),
                  format = function(x) formatC(x, format = "d", big.mark = ","))

paging_text <- paste(
  "macOS only. `page_reclaims` are cheap memory requests satisfied from a free",
  "list; `page_faults` required going to disk and are much slower; `swaps` should",
  "be zero. Non-zero swaps mean the machine ran out of memory and the timings on",
  "that run cannot be trusted."
)

# ---- 4. allocation categories that changed most -----------------------------

category_changes <- NULL
categories <- measurements |>
  filter(source == "instruments", grepl("^persistent_bytes:", metric))
if (nrow(categories) && length(refs) == 2) {
  category_changes <- categories |>
    mutate(category = sub("^persistent_bytes:", "", metric)) |>
    group_by(category, ref) |>
    summarise(bytes = median(number, na.rm = TRUE), .groups = "drop") |>
    pivot_wider(names_from = ref, values_from = bytes, values_fill = 0) |>
    mutate(difference = .data[[refs[[2]]]] - .data[[baseline_ref]]) |>
    arrange(desc(abs(difference))) |>
    head(10) |>
    mutate(across(c(all_of(refs), difference), pretty_bytes))
}

category_text <- paste(
  "macOS only. Instruments groups allocations by type. These are the ten types",
  "whose retained memory changed most between the branches -- the fastest way to",
  "see *what* the refactor changed, rather than how much."
)

# ---- 5. timing spread per phase ---------------------------------------------

timing_rows <- filter(measurements, source == "timing", !is.na(number))

samples <- if (!nrow(timing_rows)) NULL else timing_rows |>
  group_by(ref, metric) |>
  summarise(
    iterations = sum(!is.na(number)),
    median = pretty_seconds(median(number, na.rm = TRUE)),
    min = pretty_seconds(min(number, na.rm = TRUE)),
    max = pretty_seconds(max(number, na.rm = TRUE)),
    spread = ifelse(sum(!is.na(number)) < 2, "-",
                    sprintf("+/-%.1f%%",
                            (max(number, na.rm = TRUE) - min(number, na.rm = TRUE)) /
                              2 / median(number, na.rm = TRUE) * 100)),
    .groups = "drop"
  ) |>
  rename(phase = metric)

samples_text <- paste(
  "Every timing sample behind the medians in the report. `spread` is how much the",
  "measurements varied: if the difference between branches is smaller than the",
  "spread, the machine was noisier than the effect and the result is not real yet.",
  "More iterations (cpu_reps) narrow the spread."
)

# ---- write it out -----------------------------------------------------------

lines <- c(
  paste("# Additional metrics:", basename(run_dir)),
  "",
  paste0("Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S %z")),
  paste0("Refs compared: ", paste(refs, collapse = " vs ")),
  "",
  paste("These are the details the standard reports leave out. Sections appear only",
        "when the run collected that kind of data -- Valgrind sections are Linux,",
        "Instruments and /usr/bin/time sections are macOS."),
  "",
  section("Heap breakdown", heap_text, heap_breakdown),
  section("Measurement coverage", coverage_text, coverage),
  section("Time inside and outside the program", os_time_text, os_time),
  section("Paging and swapping", paging_text, paging),
  section("Allocation categories that changed most", category_text, category_changes),
  section("Timing samples and spread", samples_text, samples)
)

output_file <- file.path(run_dir, "additional_metrics.md")
writeLines(lines, output_file)

cat(paste(lines, collapse = "\n"), "\n")
message("\nWritten to ", output_file)
