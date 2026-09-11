#!/usr/bin/env bash
# Reference, not a runnable script: the gperftools recipe for profiling FIMS's
# C++ from R on Linux. Kept as the starting point for the R-profiling work
# (Rprof, jointprof), which needs exactly this environment.
#
# LD_PRELOAD has to be set before R starts, which is why R-level profiling needs
# a shell wrapper at all -- R cannot set it for itself.

LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libprofiler.so \
CPUPROFILE=/tmp/fims_cpp.prof \
CPUPROFILE_REALTIME=1 \
CPUPROFILE_FREQUENCY=50 \
Rscript -e "source(here::here('R', 'setup_FIMS.R'));
            inputs <- setup_fims_inputs(size = Sys.getenv('FIMS_SIZE', 'normal'));
            setup_fims_model(inputs, stage = Sys.getenv('FIMS_STAGE', 'initialize'))"

# gperftools appends the process id to CPUPROFILE, so the file is
# /tmp/fims_cpp.prof_<pid> -- check the actual name before opening it.
#
#   pprof -http=0.0.0.0:8080 /tmp/fims_cpp.prof_<pid>   # interactive flame graph
#   pprof --text             /tmp/fims_cpp.prof_<pid>   # top functions
