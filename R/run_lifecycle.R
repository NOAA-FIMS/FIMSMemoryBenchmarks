#!/usr/bin/env Rscript
# Back-to-back runs of one stage, in one R process, on the optimized build.
#
# A single run cannot say whether memory accumulates or how long a stage
# reliably takes, so this repeats the model's whole lifecycle -- build, run to
# the stage, clear() -- and records two things:
#
#   memory in use after each cycle   flat after the first couple of cycles
#                                    means nothing is kept; a steady rise is a
#                                    leak, and its slope is the leak per model
#   bench::mark() over the same cycle   time per cycle with its spread, the
#                                    memory R allocates, and collections
#
# Memory in use is glibc's own count of bytes handed out and not returned, which
# covers R and C++ alike. Resident memory cannot answer this -- freed memory
# stays inside the process -- and gc() sees only R's heap. So it is Linux only;
# on macOS the timing still runs.
#
# Environment:
#   REPO_ROOT, FIMS_STAGE, FIMS_SIZE, FIMS_BACKEND   as for R/single_model_run.R
#   BENCH_ITERATIONS                                 cycles per loop (default 20)
#   BENCH_REF, BENCH_VERSION                         the ref, for the rows
#   BENCH_OUT                                        where to write tidy rows

repo_root <- Sys.getenv("REPO_ROOT", getwd())
source(file.path(repo_root, "R", "setup_FIMS.R"))
# Attached, not just loaded, and chosen by R_LIBS: see R/single_model_run.R.
library(FIMS)

stage <- Sys.getenv("FIMS_STAGE", "initialize")
size <- Sys.getenv("FIMS_SIZE", "normal")
backend <- Sys.getenv("FIMS_BACKEND", "TMB")
iterations <- max(suppressWarnings(as.integer(Sys.getenv("BENCH_ITERATIONS", "20"))), 3L,
                  na.rm = TRUE)
out <- Sys.getenv("BENCH_OUT")
if (!nzchar(out)) stop("BENCH_OUT is not set.", call. = FALSE)

inputs <- setup_fims_inputs(size = size)
cycle <- function() {
  invisible(setup_fims_model(inputs, stage = stage, teardown = "clear", backend = backend))
}
# Three collections before every reading: objects with finalizers, such as those
# behind external pointers, are released a collection late, and a single pass
# left readings jumping by tens of megabytes.
collect <- function() for (i in 1:3) invisible(gc())

# glibc's count, from a two-line C helper compiled here. Building FIMS already
# needs a compiler, so this adds no dependency.
heap_in_use <- NULL
if (identical(Sys.info()[["sysname"]], "Linux")) {
  build <- file.path(tempdir(), "heap_in_use")
  dir.create(build, showWarnings = FALSE)
  file.copy(file.path(repo_root, "scripts", "heap_in_use.c"), build, overwrite = TRUE)
  previous <- setwd(build)
  status <- system2(file.path(R.home("bin"), "R"), c("CMD", "SHLIB", "heap_in_use.c"),
                    stdout = FALSE, stderr = FALSE)
  setwd(previous)
  helper <- file.path(build, paste0("heap_in_use", .Platform$dynlib.ext))
  if (identical(as.integer(status), 0L) && file.exists(helper)) {
    dyn.load(helper)
    heap_in_use <- function() .Call("heap_in_use")
  } else {
    warning("Could not compile the memory helper, so memory growth is not measured.",
            call. = FALSE)
  }
}

# --- 1. does memory accumulate? ---------------------------------------------
in_use <- rep(NA_real_, iterations)
if (!is.null(heap_in_use)) {
  for (i in seq_len(iterations)) {
    cycle()
    collect()
    in_use[[i]] <- heap_in_use()
  }
}
# The first two cycles carry one-time costs -- modules loaded and caches filled
# on first use -- so the slope is taken over the cycles after them.
settled <- in_use[-(1:2)]
growth <- if (sum(is.finite(settled)) >= 3L) {
  unname(stats::coef(stats::lm(settled ~ seq_along(settled)))[[2]])
} else NA_real_

# --- 2. how long does it take? ----------------------------------------------
# filter_gc = FALSE keeps every iteration: garbage collection is part of what
# the stage costs, and dropping those iterations would flatter it.
timing <- suppressWarnings(bench::mark(
  cycle(), iterations = iterations, check = FALSE, filter_gc = FALSE,
  memory = isTRUE(unname(capabilities("profmem")))))
times <- as.numeric(timing$time[[1]])
collections <- rowSums(as.data.frame(timing$gc[[1]]))
allocated <- as.numeric(timing$mem_alloc)

# --- rows ---------------------------------------------------------------------
as_text <- function(x) {
  if (is.finite(x) && x == round(x) && abs(x) < 1e15) {
    formatC(x, format = "f", digits = 0L)
  } else {
    format(x, digits = 15L)
  }
}
row <- function(metric, unit, value, iteration = "") {
  data.frame(metric = metric, unit = unit, value = as_text(value),
             iteration = as.character(iteration), stringsAsFactors = FALSE)
}
rows <- rbind(
  row("cycles", "count", iterations),
  if (!is.null(heap_in_use)) rbind(
    row("heap_growth_per_cycle", "bytes", growth),
    row("heap_after_first_cycle", "bytes", in_use[[1L]]),
    row("heap_after_last_cycle", "bytes", in_use[[iterations]]),
    do.call(rbind, lapply(seq_len(iterations), function(i) {
      row("heap_after_cycle", "bytes", in_use[[i]], i)
    }))
  ),
  row("median_time", "seconds", stats::median(times)),
  row("gc_per_cycle", "count", stats::median(collections)),
  if (length(allocated) == 1L && is.finite(allocated)) row("mem_alloc", "bytes", allocated),
  do.call(rbind, lapply(seq_along(times), function(i) row("time", "seconds", times[[i]], i)))
)
rows <- data.frame(
  ref = Sys.getenv("BENCH_REF"), fims_version = Sys.getenv("BENCH_VERSION"),
  stage = "", backend = "", teardown = "", size = "", round = "",
  iteration = rows$iteration, source = "lifecycle", metric = rows$metric,
  unit = rows$unit, value = rows$value, path = "", stringsAsFactors = FALSE)
utils::write.table(rows, out, sep = "\t", row.names = FALSE, quote = FALSE)
message("--> ", iterations, " back-to-back cycles written to ", out)

quit(save = "no", status = 0)
