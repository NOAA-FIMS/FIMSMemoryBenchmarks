source("R/install_FIMS_debug")

run_branch_benchmark <- function(ref) {
  install_fims_debug(ref)
  source("R/run_benchmark.R")
}

# 1. Benchmark Main
run_branch_benchmark("main") # Outputs to outputs/massif_main.out

# 2. Benchmark Feature Branch
run_branch_benchmark("xptr-refactor") # Outputs to outputs/massif_xptr.out
