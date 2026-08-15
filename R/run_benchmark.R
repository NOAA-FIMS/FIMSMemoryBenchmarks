#' Run the FIMS interface benchmark across two refs
#'
#' Top-level entry point. Installs each ref in turn and runs the requested
#' profilers against it.
#'
#' IMPORTANT: run this in an R session that has never loaded FIMS. Installing a
#' different FIMS build while its DLL is mapped into the session is unreliable.
#'
#' @param ref_first Baseline branch, tag, or commit.
#' @param ref_compare Ref compared against `ref_first`.
#' @param profiles Which profilers to run: any of "memory", "cpu", "r".
#' @param stage Which model stage to profile, passed to `setup_fims_model()`.
#' @param cpu_reps,mem_reps Repetitions per ref for the CPU and memory scripts.
#' @return Invisibly, the path to this run's output directory.
#' @examples
#' \dontrun{
#' source("R/run_benchmark.R")
#' run_fims_benchmark("main", "xptr-refactor")
#' run_fims_benchmark("main", "xptr-refactor", profiles = "memory", stage = "setup")
#' }
run_fims_benchmark <- function(ref_first = "main",
                               ref_compare = "xptr-refactor",
                               profiles = c("memory", "cpu", "r"),
                               stage = "inner",
                               cpu_reps = 5L,
                               mem_reps = 2L) {

  if ("FIMS" %in% loadedNamespaces()) {
    stop("Start a fresh R session: FIMS is already loaded, and installing a ",
         "different build over a mapped DLL is unreliable.", call. = FALSE)
  }

  profiles <- match.arg(profiles, c("memory", "cpu", "r"), several.ok = TRUE)
  refs <- c(ref_first, ref_compare)
  if (anyNA(refs) || !all(nzchar(refs))) {
    stop("Both refs must be non-empty branch, tag, or commit names.", call. = FALSE)
  }
  if (identical(ref_first, ref_compare)) {
    warning("Both refs are '", ref_first, "'; this is a self-comparison.",
            call. = FALSE)
  }

  repo_root <- normalizePath(
    if (requireNamespace("here", quietly = TRUE)) here::here() else getwd(),
    mustWork = TRUE
  )

  # R owns the run id, so the output path is known before anything runs and
  # survives a partial failure.
  run_id <- paste0(format(Sys.time(), "%Y%m%dT%H%M%SZ", tz = "UTC"), "_", Sys.getpid())
  output_dir <- file.path(repo_root, "outputs", run_id)
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

  runners <- list(
    memory = list(cmd = "bash",    script = file.path(repo_root, "scripts", "memory_profile.sh")),
    cpu    = list(cmd = "bash",    script = file.path(repo_root, "scripts", "cpu_profile.sh")),
    r      = list(cmd = "Rscript", script = file.path(repo_root, "R", "run_r_profile.R"))
  )

  env <- c(
    paste0("REPO_ROOT=",   shQuote(repo_root)),
    paste0("OUTPUT_DIR=",  shQuote(output_dir)),
    paste0("RUN_ID=",      shQuote(run_id)),
    paste0("REF_FIRST=",   shQuote(ref_first)),
    paste0("REF_COMPARE=", shQuote(ref_compare)),
    paste0("FIMS_STAGE=",  shQuote(stage)),
    paste0("CPU_REPS=",    as.integer(cpu_reps)),
    paste0("MEM_REPS=",    as.integer(mem_reps))
  )

  old <- setwd(repo_root); on.exit(setwd(old), add = TRUE)

  message(sprintf("Run %s: '%s' vs '%s' | stage=%s | profiles=%s",
                  run_id, ref_first, ref_compare, stage,
                  paste(profiles, collapse = ",")))

  status <- setNames(rep(NA_integer_, length(profiles)), profiles)

  for (p in profiles) {
    r <- runners[[p]]
    if (!file.exists(r$script)) {
      warning("Missing ", r$script, "; skipping '", p, "'.", call. = FALSE)
      status[[p]] <- NA_integer_
      next
    }
    log_file <- file.path(output_dir, paste0(p, "_profile.log"))
    message("--> ", p, " profile")
    # Sequential, never concurrent: a valgrind run alongside a CPU run would
    # invalidate the CPU numbers.
    status[[p]] <- system2(r$cmd, r$script, env = env,
                           stdout = log_file, stderr = log_file)
    if (!identical(status[[p]], 0L)) {
      warning("'", p, "' profile exited with status ", status[[p]],
              "; see ", log_file, call. = FALSE)
    }
  }

  manifest <- data.frame(
    run_id = run_id, stage = stage,
    ref_first = ref_first, ref_compare = ref_compare,
    profile = names(status), status = unname(status),
    timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    stringsAsFactors = FALSE
  )
  write.table(manifest, file.path(output_dir, "manifest.tsv"),
              sep = "\t", row.names = FALSE, quote = FALSE)

  message("Done: ", output_dir)
  print(manifest[, c("profile", "status")])
  invisible(output_dir)
}
