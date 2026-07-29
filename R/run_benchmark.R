sudo apt update && sudo apt install -y google-perftools libgoogle-perftools-dev

LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libprofiler.so \
CPUPROFILE=/tmp/fims_cpp.prof \
CPUPROFILE_REALTIME=1 \
CPUPROFILE_FREQUENCY=50 \
Rscript -e "source(here::here('R', 'setup_FIMS.R')); setup_fims_model()"

# Launch interactive browser flame graph
pprof -http=0.0.0.0:8080 /tmp/fims_cpp.prof_25712

# Or generate a top-functions text report in terminal
pprof --text /tmp/fims_cpp.prof_25712
