# reference_rows(): the reference run's saved values turned into the tidy rows
# the report reads. The values file is written here in the shape
# setup_fims_model() records, so a renamed field shows up as a failure rather
# than as a section silently missing from the report.
#
#   Rscript scripts/test_reference_rows.R

arguments <- commandArgs(FALSE)
this_file <- sub("^--file=", "", arguments[grep("^--file=", arguments)])
root <- normalizePath(file.path(dirname(this_file), ".."))
source(file.path(root, "R", "run_benchmark.R"))

standard_errors <- c(0.012, 0.045, 0.108)
values <- list(
  backend = "TMB",
  initial_parameters = list(p = c(0.5, -1.2, 2.0), re = c(0.01, 0.02)),
  n_fixed = 3L, n_random = 2L, n_par = 5L,
  initial_objective = 101.5, final_objective = 50.25,
  final_gradient = c(1e-6, -2e-6, 0),
  final_parameters = c(0.31, -1.42, 2.07, 0.01, 0.02),
  convergence = 0L, iterations = 42L, function_evaluations = 58L,
  gradient_evaluations = 43L,
  sdr_fixed = matrix(c(0.31, -1.42, 2.07, standard_errors), ncol = 2L,
                     dimnames = list(rep("p", 3L), c("Estimate", "Std. Error"))),
  random = matrix(c(0.01, 0.02, 0.004, 0.006), ncol = 2L,
                  dimnames = list(rep("re", 2L), c("Estimate", "Std. Error"))),
  report = matrix(c(1000, 950, 900, 40, 38, 36), ncol = 2L,
                  dimnames = list(c("SSB", "SSB", "recruitment"),
                                  c("Estimate", "Std. Error"))),
  stage = "sdreport", model_size = "normal",
  maximum_rss = 359000000, stage_rss_added = 81000000,
  page_reclaims = 77218, page_faults = 0)
path <- tempfile(fileext = ".rds")
saveRDS(values, path)
rows <- reference_rows("main", path, "0.10.0")
value <- function(metric) rows$value[match(metric, rows$metric)]

# Parameter values: one named row per value, from initialize_fims()'s list.
stopifnot(sum(startsWith(rows$metric, "parameter:")) == 5L,
          all(c("parameter:1:p1", "parameter:5:re2") %in% rows$metric))

# Estimates and standard errors are numbered only, since the report reads them
# back as estimate:<n> and standard_error:<n>.
stopifnot(identical(sort(rows$metric[startsWith(rows$metric, "estimate:")]),
                    paste0("estimate:", 1:5)),
          identical(rows$metric[startsWith(rows$metric, "standard_error:")],
                    paste0("standard_error:", 1:3)))

# Standard errors come from the Std. Error column of sdr_fixed.
stopifnot(identical(as.numeric(value(paste0("standard_error:", 1:3))), standard_errors),
          as.numeric(value("sd_fixed_max")) == max(standard_errors))

# The random effects and the derived quantities keep their own estimates and
# errors, named, since they are numbered apart from the parameter vector.
stopifnot(identical(as.numeric(value(c("random_estimate:1:re", "random_error:2:re"))),
                    c(0.01, 0.006)),
          identical(as.numeric(value(c("derived_estimate:1:SSB", "derived_error:3:recruitment"))),
                    c(1000, 36)),
          identical(rows$unit[startsWith(rows$metric, "derived_")], rep("value", 6L)))

# Whole numbers are written in full, not in scientific notation.
stopifnot(identical(value("maximum_rss"), "359000000"),
          identical(unique(rows$fims_version), "0.10.0"),
          identical(unique(rows$backend), "TMB"),
          all(rows$source == "reference"))

# The large model records neither summary: the comparison is made at 30 years,
# and one row per derived value per year and age would swamp results.tsv.
large <- values
large$model_size <- "large"
large_path <- tempfile(fileext = ".rds")
saveRDS(large, large_path)
large_rows <- reference_rows("main", large_path)
stopifnot(!any(grepl("^(random|derived)_", large_rows$metric)),
          sum(startsWith(large_rows$metric, "estimate:")) == 5L)

# Below optimize there is no fit, and parList() gives a named vector.
early <- list(backend = "TMB", stage = "tape", model_size = "normal",
              initial_parameters = c(p = 0.5, p = -1.2, re = 0.01))
early_path <- tempfile(fileext = ".rds")
saveRDS(early, early_path)
early_rows <- reference_rows("main", early_path)
stopifnot(sum(startsWith(early_rows$metric, "parameter:")) == 3L,
          !any(startsWith(early_rows$metric, "estimate:")),
          !"final_objective" %in% early_rows$metric)

# On macOS the memory numbers come from the /usr/bin/time -l file.
writeLines(c("  216485888  maximum resident set size",
             "  170000000  peak memory footprint",
             "      53154  page reclaims",
             "          3  page faults",
             "          0  swaps"),
           sub("[.]rds$", "_time.txt", early_path))
mac_rows <- reference_rows("main", early_path)
mac_value <- function(metric) mac_rows$value[match(metric, mac_rows$metric)]
stopifnot(identical(mac_value("maximum_rss"), "216485888"),
          identical(mac_value("peak_footprint"), "170000000"),
          identical(mac_value("swaps"), "0"))

# End to end: these rows, merged as the benchmark merges them, render the
# estimates and agreement tables with numbered rows.
run <- file.path(tempdir(), "sdreport-normal")
dir.create(run)
both <- rbind(rows, reference_rows("xptr", path, "0.10.0"))
both$stage <- "sdreport"; both$teardown <- "none"; both$size <- "normal"
both$round <- ""; both$iteration <- ""
columns <- c("ref", "fims_version", "stage", "backend", "teardown", "size",
             "round", "iteration", "source", "metric", "unit", "value", "path")
utils::write.table(both[, columns], file.path(run, "results.tsv"),
                   sep = "\t", row.names = FALSE, quote = FALSE)
writeLines(c("run_id\tlabel\tstage", "sdreport-normal\tsdreport-normal\tsdreport"),
           file.path(run, "manifest.tsv"))
report <- file.path(tempdir(), "report.md")
status <- system2("Rscript", c(shQuote(file.path(root, "R", "report.R")),
                               shQuote(report), shQuote(run)),
                  stdout = FALSE, stderr = FALSE)
stopifnot(identical(as.integer(status), 0L))
text <- readLines(report)
stopifnot("## Estimated parameters: sdreport-normal" %in% text,
          "## Random effects: sdreport-normal" %in% text,
          "## Derived quantities: sdreport-normal" %in% text,
          # Grouped by name: SSB holds two of the three derived values.
          any(grepl("^\\| SSB \\| 2 \\|", text)),
          "## Parameter values: sdreport-normal" %in% text,
          "## Do the refs agree?" %in% text,
          any(grepl("^\\| 1 \\| 0.31 \\| 0.012 \\| 0.31 \\| 0.012 \\|$", text)))

cat("Reference row checks passed\n")
