#!/usr/bin/env Rscript
# One report for a whole analysis.
#
#   Rscript R/report.R OUT.md RUN_DIR [RUN_DIR ...]
#   Rscript R/report.R --console RUN_DIR [RUN_DIR ...]
#
# Every run writes results.tsv, one tidy row per measurement, and manifest.tsv,
# which says what that run was. This reads those and nothing else: there are no
# per-run Markdown documents to stitch together, and a section appears only when
# the runs actually produced the measurement it describes. An analysis of only
# "initialize" therefore gets a memory section and no fit.
#
# --console prints the short version instead of writing the document.

args <- commandArgs(trailingOnly = TRUE)
console_only <- "--console" %in% args
args <- args[args != "--console"]
if (console_only) {
  output <- ""
  run_dirs <- args
} else {
  if (length(args) < 2L) stop("Expected OUTPUT followed by run directories.", call. = FALSE)
  output <- args[[1L]]
  run_dirs <- args[-1L]
}
run_dirs <- run_dirs[dir.exists(run_dirs)]
if (!length(run_dirs)) stop("No run directories to report on.", call. = FALSE)

# ---- read -------------------------------------------------------------------

read_tsv <- function(path) {
  if (!file.exists(path)) return(NULL)
  out <- utils::read.delim(path, colClasses = "character", check.names = FALSE)
  if (!nrow(out)) NULL else out
}

measurements <- do.call(rbind, lapply(run_dirs, function(dir) {
  rows <- read_tsv(file.path(dir, "results.tsv"))
  if (is.null(rows)) return(NULL)
  manifest <- read_tsv(file.path(dir, "manifest.tsv"))
  rows$run <- if (is.null(manifest)) basename(dir) else manifest$label[[1]]
  rows$run_dir <- basename(dir)
  rows
}))
if (is.null(measurements)) stop("No results.tsv found in any run directory.", call. = FALSE)

measurements$number <- suppressWarnings(as.numeric(measurements$value))

# The axes a run varied, one row per run, in the order the runs were given.
# Taken from rows the merge filled in first: reference rows record the backend a
# build actually used ("xptr" rather than "quadra"), which would otherwise split
# one run into two.
axes <- measurements[order(measurements$source == "reference"),
                     c("run", "stage", "backend", "teardown", "size")]
runs <- axes[!duplicated(axes$run), , drop = FALSE]
runs <- runs[order(match(runs$run, unique(measurements$run))), , drop = FALSE]
refs <- unique(measurements$ref)
refs <- refs[nzchar(refs)]

# ---- helpers ----------------------------------------------------------------

bytes <- function(value) {
  if (length(value) != 1L || is.na(value)) return("—")
  units <- c("B", "KiB", "MiB", "GiB", "TiB")
  index <- 1L
  while (abs(value) >= 1024 && index < length(units)) {
    value <- value / 1024
    index <- index + 1L
  }
  paste(format(round(value, if (index == 1L) 0L else 2L), trim = TRUE), units[[index]])
}

# Metric by run and ref, as a matrix with runs down the side and refs across.
pick <- function(source, metric) {
  hit <- measurements[measurements$source == source & measurements$metric == metric, , drop = FALSE]
  if (!nrow(hit)) return(NULL)
  out <- matrix(NA_real_, nrow(runs), length(refs), dimnames = list(runs$run, refs))
  out[cbind(match(hit$run, runs$run), match(hit$ref, refs))] <- hit$number
  out
}

# A table of one metric: runs down the side, refs across, plus the change from
# the first ref where there are two or more.
compare_table <- function(values, format_value, change) {
  # A run that never produced this metric is left out rather than shown as a
  # row of dashes: the sections are about what was measured.
  values <- values[rowSums(!is.na(values)) > 0L, , drop = FALSE]
  if (!nrow(values)) return(NULL)
  header <- c("Run", refs, if (length(refs) > 1L) paste("Change:", refs[-1L]))
  lines <- c(paste0("| ", paste(header, collapse = " | "), " |"),
             paste0("|---|", paste(rep("---:|", length(header) - 1L), collapse = "")))
  for (index in seq_len(nrow(values))) {
    row <- values[index, ]
    cells <- vapply(row, format_value, character(1))
    if (length(refs) > 1L) {
      cells <- c(cells, vapply(row[-1L], function(x) change(row[[1L]], x), character(1)))
    }
    lines <- c(lines, paste0("| ", rownames(values)[[index]], " | ",
                             paste(cells, collapse = " | "), " |"))
  }
  lines
}

change_bytes <- function(baseline, comparison) {
  if (is.na(baseline) || is.na(comparison)) return("—")
  percent <- if (baseline == 0) "" else sprintf(" (%+.1f%%)", (comparison - baseline) / baseline * 100)
  paste0(if (comparison >= baseline) "+" else "-", bytes(abs(comparison - baseline)), percent)
}

change_ratio <- function(baseline, comparison) {
  if (is.na(baseline) || is.na(comparison) || baseline == 0) return("—")
  sprintf("%+.1f%%", (comparison - baseline) / baseline * 100)
}

# A section is written only when its table has rows, so a benchmark that never
# reached a rung says nothing about it rather than printing empty headings.
seconds <- function(x) if (is.na(x)) "\u2014" else sprintf("%.3f s", x)

section <- function(title, note, table) {
  if (is.null(table)) return(character())
  c("", paste("##", title), "", note, "", table)
}

# ---- the document -----------------------------------------------------------

lines <- c(
  "# FIMS Benchmark Report", "",
  paste0("Generated: `", format(Sys.time(), tz = "UTC", usetz = TRUE), "`"), "",
  sprintf("%d run%s comparing %s. Every measurement behind this report is in `results.tsv`.",
          nrow(runs), if (nrow(runs) == 1L) "" else "s",
          paste0("`", paste(refs, collapse = "`, `"), "`")),
  "",
  "| Run | Stage | Backend | Size | Teardown |", "|---|---|---|---|---|"
)
for (index in seq_len(nrow(runs))) {
  lines <- c(lines, sprintf("| %s | %s | %s | %s | %s |", runs$run[[index]],
                            runs$stage[[index]], runs$backend[[index]],
                            runs$size[[index]], runs$teardown[[index]]))
}

# One row per run and ref: the build, and the headline resident memory. Columns
# that no run measured are left out, so Linux never shows an empty Apple-only
# peak footprint and a run without Instruments shows no Instruments column.
text_of <- function(source, metric, run, ref) {
  hit <- measurements$value[measurements$source == source & measurements$metric == metric &
                              measurements$run == run & measurements$ref == ref]
  if (!length(hit)) NA_character_ else hit[[1L]]
}
number_of <- function(source, metric, run, ref) {
  hit <- measurements$number[measurements$source == source & measurements$metric == metric &
                               measurements$run == run & measurements$ref == ref]
  if (!length(hit)) NA_real_ else hit[[1L]]
}
has <- function(source, metric) any(measurements$source == source & measurements$metric == metric)
# Linux records a status of "not run" for Instruments, which has nothing to say.
ran_instruments <- any(measurements$source == "instruments" &
                         measurements$metric == "trace_status" &
                         measurements$value != "not run")
if (has("reference", "maximum_rss")) {
  # No elapsed time here: timing belongs to bench::mark(), which repeats.
  columns <- c("Run", "Git ref", "FIMS version", "Maximum RSS",
               if (has("lifecycle", "heap_growth_per_cycle"))
    "Back-to-back memory is glibc's count of bytes in use, R and C++ together, read after three garbage collections. Resident memory cannot show a leak, because freed memory stays inside the process. It is Linux only; timing is measured everywhere.",
  if (has("reference", "peak_footprint")) "Peak footprint",
               if (ran_instruments) "Instruments")
  table <- c(paste0("| ", paste(columns, collapse = " | "), " |"),
             paste0("|---|---|---|", paste(rep("---:|", length(columns) - 3L), collapse = "")))
  for (run in runs$run) {
    for (ref in refs) {
      rss <- number_of("reference", "maximum_rss", run, ref)
      if (is.na(rss)) next
      version <- measurements$fims_version[measurements$run == run & measurements$ref == ref &
                                             nzchar(measurements$fims_version)]
      cells <- c(run, paste0("`", ref, "`"),
                 if (length(version)) version[[1L]] else "\u2014",
                 paste0("**", bytes(rss), "**"),
                 if (has("reference", "peak_footprint")) bytes(number_of("reference", "peak_footprint", run, ref)),
                 if (ran_instruments) {
                   status <- text_of("instruments", "trace_status", run, ref)
                   if (is.na(status)) "\u2014" else status
                 })
      table <- c(table, paste0("| ", paste(cells, collapse = " | "), " |"))
    }
  }
  lines <- c(lines, "", "## Summary", "",
    "Maximum resident set size is the most memory the operating system saw each process hold, from the reference run: the stage once more on the optimized build, with no profiler attached. It includes R, its packages and mapped code, so it is broader than the heap numbers below.",
    "", table)
}

# What was fitted, taken from the runs rather than restated by hand, once per
# size: the two sizes are different models with different parameter counts.
counts <- measurements[measurements$source == "reference" &
                         measurements$metric %in% c("n_fixed", "n_random") &
                         !is.na(measurements$number) & measurements$number > 0, , drop = FALSE]
if (nrow(counts)) {
  per_size <- vapply(unique(counts$size), function(size) {
    here <- counts[counts$size == size, , drop = FALSE]
    years <- if (identical(size, "large")) 120L else 30L
    sprintf("- **%s (%d years):** %s fixed and %s random parameters.", size, years,
            max(here$number[here$metric == "n_fixed"]),
            max(here$number[here$metric == "n_random"]))
  }, character(1))
  lines <- c(lines, "", "## The model", "",
    "A wrapper-built catch-at-age model with 12 ages and two fleets. Observed components are fishing catch, survey index, age and length compositions, weight at age, and the age-to-length conversion. The `large` inputs repeat the 30 years of `data_big` to reach its length, so it is the same information at greater scale rather than new observations. The random effects are one recruitment deviation per year after the first.",
    "", per_size)
}

measure <- function(source, metric, format_value = bytes, change = change_bytes) {
  values <- pick(source, metric)
  if (is.null(values)) NULL else compare_table(values, format_value, change)
}

lines <- c(lines, section(
  "Memory the stage is responsible for",
  "Peak heap with the inputs-only baseline subtracted, so what is left is what the interface allocated. This is the number the comparison rests on.",
  measure("massif", "stage_peak")))

lines <- c(lines, section(
  "Memory the stage added (reference run)",
  "The most resident memory the stage added on top of what the process held when it started, from the reference run on the optimized build. Unlike the Massif number above, it does not vanish when the stage stays below the peak that building the data already set. Linux only.",
  measure("reference", "stage_rss_added")))

lines <- c(lines, section(
  "Peak heap of the whole process",
  "Everything the process held at its high-water mark, R and its dependencies included.",
  measure("massif", "peak_total")))

lines <- c(lines, section(
  "The inputs baseline",
  "Each ref was also profiled building the inputs and stopping before the stage. This is that run, and it is what the stage numbers above already have subtracted: R start-up, the data, and the parameter edits, which are identical across refs.",
  measure("massif", "inputs_peak")))

lines <- c(lines, section(
  "Memory still held at exit",
  "What the stage had not released when the process ended. Compare the `clear` and `release` runs with the run that tore nothing down: that difference is what teardown actually returns.",
  measure("massif", "stage_retained")))

# Runs down the side, one row per metric, refs across. The same shape as the
# sections above, for groups of related metrics rather than a single one.
metric_table <- function(source, labels, bytes_metrics = character(),
                         prefix = NULL, percent = FALSE) {
  if (!is.null(prefix)) {
    present <- unique(measurements$metric[measurements$source == source &
                                            startsWith(measurements$metric, prefix)])
    labels <- stats::setNames(sub(prefix, "", present), present)
  }
  labels <- labels[vapply(names(labels), function(m) has(source, m), logical(1))]
  if (!length(labels)) return(NULL)
  header <- c("Run", "Metric", refs, if (length(refs) > 1L) paste("Change:", refs[-1L]))
  table <- c(paste0("| ", paste(header, collapse = " | "), " |"),
             paste0("|---|---|", paste(rep("---:|", length(header) - 2L), collapse = "")))
  for (run in runs$run) {
    for (metric in names(labels)) {
      row <- vapply(refs, function(ref) number_of(source, metric, run, ref), numeric(1))
      if (all(is.na(row))) next
      is_bytes <- !percent && (metric %in% bytes_metrics || !is.null(prefix))
      shown <- vapply(row, function(x) {
        if (is.na(x)) "\u2014"
        else if (percent) sprintf("%.2f%%", x)
        else if (is_bytes) bytes(x)
        else formatC(x, format = "d", big.mark = ",")
      }, character(1))
      changes <- if (length(refs) > 1L) vapply(row[-1L], function(x) {
        if (is_bytes) change_bytes(row[[1L]], x) else change_ratio(row[[1L]], x)
      }, character(1))
      table <- c(table, paste0("| ", run, " | ", labels[[metric]], " | ",
                               paste(c(shown, changes), collapse = " | "), " |"))
    }
  }
  if (length(table) > 2L) table else NULL
}

lines <- c(lines, section(
  "What the peak was made of",
  "The peak split into what the program asked for, what the allocator spent on bookkeeping and alignment, and stack memory. A branch that lowers the heap but raises overhead has changed how it allocates, not how much. Stacks are zero unless Massif is run with `--stacks=yes`. Retained is the whole process at exit, where the section above is the stage's share of it.",
  metric_table("massif",
               c(peak_heap = "Heap", peak_extra = "Allocator overhead",
                 peak_stacks = "Stacks", retained_total = "Retained at exit"),
               bytes_metrics = c("peak_heap", "peak_extra", "peak_stacks", "retained_total"))))

lines <- c(lines, section(
  "How well the run was sampled",
  "Bookkeeping rather than results. Massif samples memory as a program allocates, so too few snapshots means the true peak may sit between them. Processes is how many Valgrind traced, since `Rscript` execs the real R binary and R can spawn children.",
  metric_table("massif", c(snapshots = "Snapshots", processes = "Processes"))))

# Every operating-system memory measure, per run, with the change from the
# first ref. Rows no run measured are dropped, as everywhere else.
detail <- c(maximum_rss = "Maximum RSS", peak_footprint = "Peak footprint",
            page_reclaims = "Page reclaims", page_faults = "Page faults", swaps = "Swaps")
detail <- detail[vapply(names(detail), function(m) has("reference", m), logical(1))]
if (length(detail)) {
  header <- c("Run", "Metric", refs, if (length(refs) > 1L) paste("Change:", refs[-1L]))
  table <- c(paste0("| ", paste(header, collapse = " | "), " |"),
             paste0("|---|---|", paste(rep("---:|", length(header) - 2L), collapse = "")))
  for (run in runs$run) {
    for (metric in names(detail)) {
      row <- vapply(refs, function(ref) number_of("reference", metric, run, ref), numeric(1))
      if (all(is.na(row))) next
      is_bytes <- metric %in% c("maximum_rss", "peak_footprint")
      shown <- vapply(row, function(x) {
        if (is.na(x)) "\u2014" else if (is_bytes) bytes(x) else formatC(x, format = "d", big.mark = ",")
      }, character(1))
      changes <- if (length(refs) > 1L) vapply(row[-1L], function(x) {
        if (is_bytes) change_bytes(row[[1L]], x) else change_ratio(row[[1L]], x)
      }, character(1))
      table <- c(table, paste0("| ", run, " | ", detail[[metric]], " | ",
                               paste(c(shown, changes), collapse = " | "), " |"))
    }
  }
  lines <- c(lines, section(
    "Detailed branch comparison",
    "From the reference run. Page reclaims are memory requests met without touching disk and are cheap. Page faults needed disk and are slow. Swaps should be zero: any swap means the machine ran out of memory, and timings from that run cannot be trusted.",
    table))
}

# Agreement: the fit has to match between refs, or a speed difference means
# nothing. Only runs that reached the optimize rung have one.
objective <- pick("reference", "final_objective")
if (!is.null(objective) && length(refs) > 1L) {
  lines <- c(lines, "", "## Do the refs agree?", "",
    "Each ref fits the same model from the same starting values with the same `nlminb` controls, so these should agree to optimizer tolerance.", "")
  metrics <- c(initial_objective = "Initial objective",
               final_objective = "Final objective",
               final_gradient_max = "Largest final gradient",
               sd_fixed_max = "Largest standard error",
               convergence = "Convergence code", iterations = "Iterations",
               function_evaluations = "Objective evaluations",
               gradient_evaluations = "Gradient evaluations",
               n_fixed = "Fixed effects", n_random = "Random effects")
  header <- c("Run", "Metric", refs, paste("Difference:", refs[-1L]))
  lines <- c(lines, paste0("| ", paste(header, collapse = " | "), " |"),
             paste0("|---|---|", paste(rep("---:|", length(header) - 2L), collapse = "")))
  available <- lapply(names(metrics), function(metric) pick("reference", metric))
  names(available) <- names(metrics)
  # Run-major, so everything about one fit is read together.
  for (run_index in seq_len(nrow(runs))) {
    for (metric in names(metrics)) {
      values <- available[[metric]]
      if (is.null(values)) next
      row <- values[run_index, ]
      if (all(is.na(row))) next
      shown <- vapply(row, function(x) if (is.na(x)) "\u2014" else format(x, digits = 12L), character(1))
      differences <- vapply(row[-1L], function(x) {
        if (is.na(x) || is.na(row[[1L]])) "\u2014" else format(abs(x - row[[1L]]), digits = 4L)
      }, character(1))
      lines <- c(lines, paste0("| ", runs$run[[run_index]], " | ", metrics[[metric]],
                               " | ", paste(c(shown, differences), collapse = " | "), " |"))
    }
  }
}

# Every estimate, with its standard error where the run reached sdreport. This
# is the comparison the fit is for: agreeing on the objective while disagreeing
# on a parameter would mean the two builds found different optima.
estimates <- measurements[measurements$source == "reference" &
                            startsWith(measurements$metric, "estimate:"), , drop = FALSE]
if (nrow(estimates)) {
  for (run in unique(estimates$run)) {
    indices <- sort(unique(as.integer(sub("^estimate:", "",
                                          estimates$metric[estimates$run == run]))))
    has_errors <- any(startsWith(measurements$metric, "standard_error:") &
                        measurements$run == run)
    value_of <- function(ref, metric) {
      hit <- measurements$number[measurements$run == run & measurements$ref == ref &
                                   measurements$metric == metric]
      if (!length(hit)) NA_real_ else hit[[1L]]
    }
    columns <- if (has_errors) paste(rep(refs, each = 2L), c("estimate", "SE")) else refs
    table <- c(paste0("| # | ", paste(columns, collapse = " | "), " |"),
               paste0("|---:|", paste(rep("---:|", length(columns)), collapse = "")))
    for (index in indices) {
      cells <- unlist(lapply(refs, function(ref) {
        estimate <- value_of(ref, paste0("estimate:", index))
        shown <- if (is.na(estimate)) "\u2014" else format(estimate, digits = 10L)
        if (!has_errors) return(shown)
        error <- value_of(ref, paste0("standard_error:", index))
        c(shown, if (is.na(error)) "\u2014" else format(error, digits = 6L))
      }))
      table <- c(table, paste0("| ", index, " | ", paste(cells, collapse = " | "), " |"))
    }
    lines <- c(lines, section(
      paste0("Estimated parameters: ", run),
      if (has_errors) {
        "Fixed and random effect estimates in the order the wrapper built them, with the standard errors `sdreport` returned for the fixed effects."
      } else {
        "Fixed and random effect estimates in the order the wrapper built them. Standard errors need the `sdreport` rung."
      },
      table))
  }
}

# sdreport also returns standard errors for the random effects and for the
# derived quantities, each as its own summary. Both are read here: the random
# effects one by one, and the derived quantities grouped by name, since there is
# one of those per year -- or per year and age -- and the question about them is
# only whether the refs agree.
sdreport_summary <- function(kind, run) {
  hit <- measurements[measurements$run == run &
                        startsWith(measurements$metric, paste0(kind, "_")), , drop = FALSE]
  if (!nrow(hit)) return(NULL)
  field <- sub("^[a-z]+_([a-z]+):.*$", "\\1", hit$metric)   # estimate or error
  tag <- sub("^[a-z]+_[a-z]+:", "", hit$metric)             # <index>:<name>
  tags <- unique(tag)
  tags <- tags[order(as.integer(sub(":.*$", "", tags)))]
  values <- function(which) {
    out <- matrix(NA_real_, length(tags), length(refs), dimnames = list(tags, refs))
    keep <- field == which
    out[cbind(match(tag[keep], tags), match(hit$ref[keep], refs))] <- hit$number[keep]
    out
  }
  list(name = sub("^[0-9]+:", "", tags), index = sub(":.*$", "", tags),
       estimate = values("estimate"), error = values("error"))
}

number <- function(x, digits) if (is.na(x)) "\u2014" else format(x, digits = digits)

for (run in runs$run) {
  random <- sdreport_summary("random", run)
  if (is.null(random)) next
  columns <- paste(rep(refs, each = 2L), c("estimate", "SE"))
  table <- c(paste0("| # | ", paste(columns, collapse = " | "), " |"),
             paste0("|---:|", paste(rep("---:|", length(columns)), collapse = "")))
  for (index in seq_along(random$name)) {
    cells <- unlist(lapply(seq_along(refs), function(ref) {
      c(number(random$estimate[index, ref], 10L), number(random$error[index, ref], 6L))
    }))
    table <- c(table, paste0("| ", random$index[[index]], " | ",
                             paste(cells, collapse = " | "), " |"))
  }
  lines <- c(lines, section(
    paste0("Random effects: ", run),
    "The random effects and their standard errors, from `summary(sdreport, \"random\")`. These are conditional modes, so two builds that agree on the fixed effects and disagree here have found different random effect solutions at the same optimum.",
    table))
}

for (run in runs$run) {
  derived <- sdreport_summary("derived", run)
  if (is.null(derived)) next
  header <- c("Quantity", "Values", paste("Largest SE:", refs),
              if (length(refs) > 1L) paste("Largest difference:", refs[-1L]))
  table <- c(paste0("| ", paste(header, collapse = " | "), " |"),
             paste0("|---|", paste(rep("---:|", length(header) - 1L), collapse = "")))
  for (name in unique(derived$name)) {
    rows <- which(derived$name == name)
    worst <- function(x) if (all(is.na(x))) NA_real_ else max(abs(x), na.rm = TRUE)
    errors <- vapply(seq_along(refs), function(ref) worst(derived$error[rows, ref]), numeric(1))
    differences <- if (length(refs) > 1L) {
      vapply(seq_along(refs)[-1L], function(ref) {
        worst(derived$estimate[rows, ref] - derived$estimate[rows, 1L])
      }, numeric(1))
    }
    cells <- c(vapply(errors, number, character(1), digits = 6L),
               vapply(differences, number, character(1), digits = 4L))
    table <- c(table, paste0("| ", name, " | ", length(rows), " | ",
                             paste(cells, collapse = " | "), " |"))
  }
  lines <- c(lines, section(
    paste0("Derived quantities: ", run),
    "What `sdreport` returned for the quantities the model reports, grouped by name: how many values each holds, the largest standard error among them, and the largest difference between refs. Every value is in `results.tsv`.",
    table))
}

# Back-to-back runs: the stage built, run and cleared repeatedly in one process.
# Memory growth per cycle is the leak question; the rest is bench::mark().
lifecycle <- c(heap_growth_per_cycle = "Memory growth per cycle",
               heap_after_first_cycle = "Memory in use after the first cycle",
               heap_after_last_cycle = "Memory in use after the last cycle",
               median_time = "Median time per cycle",
               mem_alloc = "R memory allocated per cycle",
               gc_per_cycle = "Garbage collections per cycle")
if (any(measurements$source == "lifecycle")) {
  header <- c("Run", "Metric", refs, if (length(refs) > 1L) paste("Change:", refs[-1L]))
  table <- c(paste0("| ", paste(header, collapse = " | "), " |"),
             paste0("|---|---|", paste(rep("---:|", length(header) - 2L), collapse = "")))
  for (run in runs$run) {
    for (metric in names(lifecycle)) {
      row <- vapply(refs, function(ref) number_of("lifecycle", metric, run, ref), numeric(1))
      if (all(is.na(row))) next
      is_bytes <- metric %in% c("heap_growth_per_cycle", "heap_after_first_cycle",
                                "heap_after_last_cycle", "mem_alloc")
      shown <- vapply(row, function(x) {
        if (is.na(x)) "\u2014" else if (is_bytes) bytes(x)
        else if (metric == "median_time") seconds(x) else format(x, digits = 3L)
      }, character(1))
      changes <- if (length(refs) > 1L) vapply(row[-1L], function(x) {
        if (is_bytes) change_bytes(row[[1L]], x) else change_ratio(row[[1L]], x)
      }, character(1))
      table <- c(table, paste0("| ", run, " | ", lifecycle[[metric]], " | ",
                               paste(c(shown, changes), collapse = " | "), " |"))
    }
  }
  cycles <- suppressWarnings(max(measurements$number[measurements$source == "lifecycle" &
                                                       measurements$metric == "cycles"], na.rm = TRUE))
  lines <- c(lines, section(
    "Back-to-back runs",
    paste0("The stage built and run ", cycles, " times in one process, on the optimized build with no profiler, tearing down each cycle the way the run does. ",
           "Memory growth is the slope of memory still in use after each cycle, leaving out the first two, which carry one-time costs: near zero means nothing accumulates, and a steady positive value is a leak of that size per model built. ",
           "Timing, R allocation and collections come from `bench::mark()` over the same cycle."),
    table))
}

# Below optimize there is no fit, but the model already holds parameter values,
# and two builds that disagree there will disagree about everything after.
parameters <- measurements[measurements$source == "reference" &
                             startsWith(measurements$metric, "parameter:"), , drop = FALSE]
if (nrow(parameters)) {
  parameters$index <- as.integer(sub("^parameter:([0-9]+):.*$", "\\1", parameters$metric))
  parameters$label <- sub("^parameter:[0-9]+:", "", parameters$metric)
  for (run in unique(parameters$run)) {
    here <- parameters[parameters$run == run, , drop = FALSE]
    counts <- tapply(here$index, here$ref, max)
    header <- c("#", "Name", paste0("`", refs, "`"),
                if (length(refs) > 1L) paste("Difference:", refs[-1L]))
    table <- c(paste0("| ", paste(header, collapse = " | "), " |"),
               paste0("|---:|---|", paste(rep("---:|", length(header) - 2L), collapse = "")))
    for (index in sort(unique(here$index))) {
      row <- vapply(refs, function(ref) {
        hit <- here$number[here$ref == ref & here$index == index]
        if (!length(hit)) NA_real_ else hit[[1L]]
      }, numeric(1))
      label <- here$label[here$index == index & here$ref == refs[[1L]]]
      shown <- vapply(row, function(x) if (is.na(x)) "\u2014" else format(x, digits = 10L), character(1))
      differences <- if (length(refs) > 1L) vapply(row[-1L], function(x) {
        if (is.na(x) || is.na(row[[1L]])) "\u2014" else format(abs(x - row[[1L]]), digits = 4L)
      }, character(1))
      table <- c(table, paste0("| ", index, " | `", if (length(label)) label[[1L]] else "", "` | ",
                               paste(c(shown, differences), collapse = " | "), " |"))
    }
    # Where the values were read is recorded alongside them; older rows, or a
    # run whose producer did not record it, simply leave that phrase out.
    from <- unique(here$path[nzchar(here$path)])
    mismatch <- if (length(unique(counts)) > 1L) {
      " The refs hold different numbers of parameters, which is itself a disagreement, so rows line up only as far as both go."
    } else ""
    lines <- c(lines, section(
      paste0("Parameter values: ", run),
      paste0("The values each ref's model holds at the end of the rung",
             if (length(from)) paste0(", read with `", paste(from, collapse = "`, `"), "`"),
             ", from the reference run. Rows are matched by position.", mismatch),
      table))
  }
}

# What allocated the peak, which is the question a total cannot answer.
origins <- measurements[measurements$source == "massif" &
                          startsWith(measurements$metric, "origin:"), , drop = FALSE]
if (nrow(origins)) {
  names <- unique(sub("^origin:", "", origins$metric))
  header <- c("Run", "Allocated by", refs)
  table <- c(paste0("| ", paste(header, collapse = " | "), " |"),
             paste0("|---|---|", paste(rep("---:|", length(refs)), collapse = "")))
  for (run in runs$run) {
    for (name in names) {
      cells <- vapply(refs, function(ref) {
        hit <- origins$number[origins$run == run & origins$ref == ref &
                                origins$metric == paste0("origin:", name)]
        if (!length(hit)) "\u2014" else bytes(hit[[1L]])
      }, character(1))
      if (all(cells == "\u2014")) next
      table <- c(table, paste0("| ", run, " | ", name, " | ",
                               paste(cells, collapse = " | "), " |"))
    }
  }
  lines <- c(lines, section(
    "What allocated the peak",
    "Leaf bytes at the peak snapshot, grouped by whose code they were allocated for: the nearest FIMS, TMB, Quadra or Rcpp frame on the allocation's stack. \"R runtime\" is memory with no such frame, which includes objects created by R code, FIMS's own R functions among them, since R code never appears on a C stack. Unresolved stacks are counted as such rather than attributed.",
    table))
}

# CPU symbols are per ref rather than per run, and there are many, so only the
# heaviest few are worth a table.
symbols <- measurements[measurements$source == "cpu" &
                          startsWith(measurements$metric, "symbol:"), , drop = FALSE]
if (nrow(symbols)) {
  lines <- c(lines, "", "## Where the CPU time goes", "",
    "Self time by symbol, from the profiled run. A profiler distorts absolute time, so read the ranking rather than the numbers.")
  for (run in unique(symbols$run)) {
    for (ref in refs) {
      hit <- symbols[symbols$run == run & symbols$ref == ref, , drop = FALSE]
      if (!nrow(hit)) next
      hit <- hit[order(-hit$number), , drop = FALSE]
      hit <- utils::head(hit, 10L)
      lines <- c(lines, "", paste0("**", run, " — `", ref, "`**"), "",
                 "| Share | Symbol |", "|---:|---|",
                 sprintf("| %.2f%% | `%s` |", hit$number,
                         gsub("|", "\\|", sub("^symbol:", "", hit$metric), fixed = TRUE)))
    }
  }
}

# The same samples as above, grouped by the library they landed in: the coarse
# view of how much time is FIMS's own code and how much is R's evaluator.
lines <- c(lines, section(
  "Where the CPU time goes, by library",
  "The same samples grouped by shared object. `FIMS.so` is the interface code under test; `libR.so` is R's own evaluator, and time there is the R side of a call rather than the C++ side. Shares are of sampled time, so they do not sum to 100. Linux only.",
  metric_table("cpu", NULL, prefix = "library:", percent = TRUE)))

# Said whether or not any symbols came back: a profiler that recorded nothing is
# the normal outcome on a kernel with no PMU, and silence would read as "no CPU
# cost" rather than "no measurement".
status <- measurements[measurements$source == "cpu" & measurements$metric == "status", , drop = FALSE]
if (nrow(status) && !any(startsWith(status$value, "captured"))) {
  lines <- c(lines, "", "## Where the CPU time goes", "",
    paste0("No CPU profile recorded any samples, so this analysis says nothing about CPU cost. ",
           "The memory numbers are unaffected. See \"Fixing Valgrind and perf installation\" in README.md."))
}

# Valgrind writes one file per process because --trace-children is on, so a peak
# is the largest of several. This is the breakdown behind that number.
processes <- measurements[measurements$source == "massif" &
                            measurements$metric == "process_peak_total", , drop = FALSE]
if (nrow(processes) > length(refs) * nrow(runs)) {
  table <- c("| Run | Ref | Process | Peak |", "|---|---|---|---:|")
  for (index in order(processes$run, processes$ref, -processes$number)) {
    table <- c(table, sprintf("| %s | %s | `%s` | %s |",
                              processes$run[[index]], processes$ref[[index]],
                              processes$path[[index]], bytes(processes$number[[index]])))
  }
  lines <- c(lines, section(
    "Every process Valgrind recorded",
    "`--trace-children` is required because `Rscript` execs the real R binary, so each run leaves one file per process. The peaks above are the largest of these.",
    table))
}

# macOS only: Instruments groups allocations by type, which says what changed
# rather than how much.
lines <- c(lines, section(
  "Allocation categories",
  "macOS only. Instruments groups still-live allocations by type at the end of the run. This is the fastest way to see *what* an interface change moved, rather than how much it moved.",
  metric_table("instruments", NULL, prefix = "persistent_bytes:")))

# Leaks laid out like every other section: runs and categories down the side,
# refs across, byte counts readable.
leaks <- measurements[measurements$source == "leaks", , drop = FALSE]
if (nrow(leaks)) {
  categories <- c(status = "Status", "definitely lost" = "Definitely lost",
                  "indirectly lost" = "Indirectly lost", "possibly lost" = "Possibly lost",
                  "still reachable" = "Still reachable", suppressed = "Suppressed",
                  leaked_bytes = "Leaked", leak_count = "Leak count")
  table <- c(paste0("| Run | Category | ", paste(paste0("`", refs, "`"), collapse = " | "), " |"),
             paste0("|---|---|", paste(rep("---:|", length(refs)), collapse = "")))
  for (run in runs$run) {
    for (metric in names(categories)) {
      cells <- vapply(refs, function(ref) {
        hit <- leaks[leaks$run == run & leaks$ref == ref & leaks$metric == metric, , drop = FALSE]
        if (!nrow(hit)) return("\u2014")
        if (identical(metric, "status")) return(hit$value[[1L]])
        if (identical(metric, "leak_count")) return(format(hit$number[[1L]], big.mark = ","))
        bytes(hit$number[[1L]])
      }, character(1))
      if (all(cells == "\u2014")) next
      table <- c(table, paste0("| ", run, " | ", categories[[metric]], " | ",
                               paste(cells, collapse = " | "), " |"))
    }
  }
  lines <- c(lines, section(
    "Leaks at process exit",
    "The stage once more under a leak detector, on the debug build so stacks resolve. Covers the whole R process, dependencies included. Definitely, indirectly and possibly lost memory are leaks; still reachable is memory R held at exit on purpose and is not. Read the allocation stacks in the raw log before attributing a leak to FIMS.",
    table))
}

lines <- c(lines, section(
  "Build cost",
  "Peak resident memory of the install that produced each library. A change that halves run time but doubles compile time is worth seeing.",
  measure("build", "peak_rss")))

# How to read what is above. Only notes for measurements this analysis took.
notes <- c(
  "Compare refs only within a run: the same model, inputs, stage, size and backend.",
  if (has("reference", "maximum_rss"))
    "Maximum RSS includes resident code and mapped pages, so it is broader than Massif heap usage and the two should not be compared directly.",
  if (has("reference", "maximum_rss"))
    "Peak RSS comes from the reference run on the optimized build: the kernel's `VmHWM` on Linux, `/usr/bin/time -l` on macOS. Swaps are reported only on macOS.",
  if (has("reference", "stage_rss_added"))
    "Memory the stage added is the kernel's high-water mark, reset just before the stage, minus the resident memory at that moment. Memory the allocator keeps after a free still counts, so it is an upper bound on what the stage needed.",
  if (has("reference", "peak_footprint"))
    "Peak footprint is Apple's accounting of the process's physical-memory impact and may be lower than RSS.",
  if (has("massif", "peak_extra"))
    "Heap overhead is Massif's estimate of allocator bookkeeping and alignment. A branch that lowers heap but raises overhead has changed its allocation pattern, not just its size.",
  if (has("massif", "peak_stacks"))
    "Stack memory is zero unless Massif stack profiling is enabled with `--stacks=yes`.",
  if (any(startsWith(measurements$metric, "origin:")))
    "Allocation origins use leaf bytes from the peak snapshot's complete stack paths. Run `ms_print` on a Massif output file for the full allocation tree and snapshot graph.",
  if (any(startsWith(measurements$metric, "symbol:0x")))
    "CPU symbols shown as hexadecimal addresses could not be resolved, usually because that library, often `libR.so`, was built without debug symbols. The ranking is still valid; only the names are missing. See \"Naming CPU symbols in libR.so\" in README.md.",
  if (nrow(leaks))
    "Leak categories are not comparable across detectors: memcheck separates definitely, indirectly and possibly lost memory, macOS `leaks` reports unreachable blocks. A leak check that failed, was disabled or was unavailable is not a clean result.",
  if (ran_instruments)
    "The Instruments `.trace` bundle is the authoritative allocation record; exported XML is provided for automation.",
  "macOS and Linux results come from different profilers and should be compared within a platform, not across them."
)
lines <- c(lines, "", "## Interpretation notes", "", paste("-", notes))

# ---- console ----------------------------------------------------------------

# The same numbers as the document, short enough to read as a run finishes.
console <- function() {
  blocks <- list(c(source = "massif", metric = "stage_peak",
                   label = "Stage-attributable peak", kind = "bytes"),
                 c(source = "massif", metric = "peak_total",
                   label = "Process peak heap", kind = "bytes"),
                 c(source = "reference", metric = "maximum_rss",
                   label = "Peak RSS (reference run)", kind = "bytes"),
                 c(source = "lifecycle", metric = "heap_growth_per_cycle",
                   label = "Memory growth per cycle", kind = "bytes"),
                 c(source = "lifecycle", metric = "median_time",
                   label = "Median time per cycle", kind = "seconds"))
  out <- c("", paste0(nrow(runs), " run(s): ", paste(refs, collapse = " vs ")))
  for (block in blocks) {
    values <- pick(block[["source"]], block[["metric"]])
    if (is.null(values)) next
    values <- values[rowSums(!is.na(values)) > 0L, , drop = FALSE]
    if (!nrow(values)) next
    cells <- apply(values, c(1, 2), function(x) {
      if (identical(block[["kind"]], "bytes")) bytes(x) else seconds(x)
    })
    width <- max(nchar(c(cells, refs))) + 2L
    name_width <- max(nchar(rownames(values))) + 2L
    out <- c(out, "", block[["label"]],
             paste0("  ", formatC("", width = name_width),
                    paste(formatC(refs, width = width), collapse = "")))
    for (index in seq_len(nrow(values))) {
      out <- c(out, paste0("  ", formatC(rownames(values)[[index]], width = -name_width),
                           paste(formatC(cells[index, ], width = width), collapse = "")))
    }
  }
  paste(c(out, ""), collapse = "\n")
}

if (console_only) {
  cat(console(), "\n")
} else {
  writeLines(lines, output)
  cat("Report written to", output, "\n")
  cat(console(), "\n")
}
