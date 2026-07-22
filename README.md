# FIMSMemoryBenchmarks

A repository to benchmark and compare the memory footprint of NOAA-FIMS/FIMS builds.

## Repository Layout

- `/R`: Helper R scripts for setup and benchmark stage execution.
- `/scripts`: Shell runners for memory profiling tools.
- `/outputs`: Benchmark and profiler outputs (`.gitkeep` included).
- `/.devcontainer`: Codespaces setup for debug-safe R compilation flags.

## Debug Build Configuration in Codespaces

This repository includes `.devcontainer/postCreate.sh`, which configures `~/.R/Makevars` with:

- `PKG_CXXFLAGS += -g -O0 -fno-omit-frame-pointer -fvisibility=default`
- `PKG_STRIP = true`

These settings preserve symbols and frame pointers for profiler-friendly builds.

## Install FIMS in Debug Mode

`R/setup_FIMS` provides:

```r
install_fims_debug(ref = "main")
```

It installs `NOAA-FIMS/FIMS` from GitHub for a chosen branch/tag/commit using source compilation.

## Benchmark Stages

`R/run_benchmark.R` is structured into five stages:

1. Static model construction through `MakeADFun()`
2. Single evaluation calls (`obj$fn()` and `obj$gr()`)
3. Full optimization run with `nlminb` (without `sdreport`)
4. Full optimization run with `nlminb` and `sdreport`
5. Cleanup and retention check via `TMB::FreeADFun(obj)` and `gc()`

> Before sourcing `R/run_benchmark.R`, define `fims_stage1_builder()` so it returns the stage-1 `MakeADFun()` object.

## Run Massif Benchmarks

```bash
bash scripts/run_massif.sh
```

This generates:

- `outputs/massif_main.out`
- `outputs/massif_xptr.out`

Use `ms_print` to inspect each output file.
