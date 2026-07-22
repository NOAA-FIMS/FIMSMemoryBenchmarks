if (!requireNamespace("TMB", quietly = TRUE)) {
  stop("Package 'TMB' is required for benchmark stages.")
}

cat("Stage 1: Static model construction through MakeADFun()\n")
if (exists("fims_stage1_builder", mode = "function")) {
  obj <- fims_stage1_builder()
} else {
  stop(
    paste(
      "Define function `fims_stage1_builder()` before sourcing R/run_benchmark.R.",
      "It must construct the model and return the object from MakeADFun()."
    )
  )
}

cat("Stage 2: Single evaluation calls (obj$fn() and obj$gr())\n")
obj$fn()
obj$gr()

cat("Stage 3: Full model run with nlminb (without sdreport)\n")
opt <- nlminb(start = obj$par, objective = obj$fn, gradient = obj$gr)

cat("Stage 4: Full model run with nlminb and sdreport\n")
obj$env$last.par.best <- opt$par
TMB::sdreport(obj)

cat("Stage 5: Cleanup and retention check (FreeADFun + gc)\n")
TMB::FreeADFun(obj)
rm(obj, opt)
invisible(gc())
