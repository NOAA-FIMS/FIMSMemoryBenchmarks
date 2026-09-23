#!/usr/bin/env bash
# Record the memory profile of ONE measurement.
#
# This wraps a profiler around run_model_for_cpp_profiler() and nothing else: no installs, no
# loops, no reporting. run_fims_benchmark() in R/run_benchmark.R owns all of
# that and calls this once per ref per round, so you can also run it by hand to
# reproduce a single profile.
#
#   R_LIBS=outputs/.lib-cache/debug/main FIMS_STAGE=initialize FIMS_SIZE=normal \
#     scripts/memory.sh --tool massif --out outputs/<run>/massif_main.out
#
# The model settings come from the environment: R_LIBS picks the build, and
# FIMS_STAGE, FIMS_SIZE, FIMS_BACKEND, TEARDOWN, STAGE_MODE and FIMS_N_EVAL are
# read by run_model_for_cpp_profiler(). This wrapper only decides the profiler.
#
# --tool massif        Valgrind Massif (Linux)
# --tool time          /usr/bin/time -l (macOS)
# --tool instruments   Instruments Allocations (macOS)
#
# -e: exit on command failure
# -u: fail on unset variables
# -o pipefail: fail a pipeline if any command in it fails
set -euo pipefail

TOOL=""
OUT=""
LOG=""
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export REPO_ROOT
ATTACH_DELAY="${FIMS_INSTRUMENTS_ATTACH_DELAY:-6}"
TIME_LIMIT="${INSTRUMENTS_TIME_LIMIT:-30m}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tool) TOOL="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --log) LOG="$2"; shift 2 ;;
    --attach-delay) ATTACH_DELAY="$2"; shift 2 ;;
    --time-limit) TIME_LIMIT="$2"; shift 2 ;;
    *) echo "Error: unknown argument '$1'." >&2; exit 2 ;;
  esac
done

if [[ -z "${R_LIBS:-}" ]]; then
  echo "Error: R_LIBS must point at the FIMS build to measure." >&2
  exit 2
fi

for required in TOOL OUT; do
  if [[ -z "${!required}" ]]; then
    echo "Error: --${required,,} is required." >&2
    exit 2
  fi
done

WORKLOAD="$REPO_ROOT/R/run_model_for_profilers.R"
# The file only defines functions, so the process sources it and calls one.
WORKLOAD_CALL="source(file.path(Sys.getenv('REPO_ROOT'), 'R', 'run_model_for_profilers.R')); run_model_for_cpp_profiler()"
[[ -f "$WORKLOAD" ]] || { echo "Error: $WORKLOAD is missing." >&2; exit 1; }
[[ -n "$LOG" ]] || LOG="${OUT}.log"

# Every tool runs this same command, so the recordings describe the same work.
DELAY_FOR_RUN=0

run_workload() {
  # Every model setting arrives in the environment from
  # run_fims_benchmark(); the only thing this wrapper decides is when the
  # recorder starts.
  STAGE_ATTACH_DELAY="$DELAY_FOR_RUN" "$@"
}

case "$TOOL" in
  massif)
    command -v valgrind >/dev/null 2>&1 || { echo "Error: valgrind not found. See \"Fixing Valgrind and perf installation\" in README.md." >&2; exit 1; }
    echo "=== Massif: stage=${FIMS_STAGE:-initialize} mode=${STAGE_MODE:-stage} -> ${OUT}_<pid> ==="
    # Massif's defaults exist for a reason: --threshold=0 keeps every entry in
    # every detailed snapshot tree, which on R plus TMB stacks produced output
    # files approaching a gigabyte per process and filled the disk.
    # --trace-children is required, not optional: Rscript is a launcher that
    # execs the real R binary, and without this Valgrind stops at the exec and
    # writes no output at all. It also means one file per process, so
    # summarize_massif.py takes the largest peak.
    run_workload valgrind --tool=massif \
      --trace-children=yes \
      --trace-children-skip=/bin/*,/usr/bin/* \
      --massif-out-file="${OUT}_%p" \
      --log-file="$LOG" \
      Rscript -e "$WORKLOAD_CALL"
    ;;

  time)
    echo "=== /usr/bin/time -l: stage=${FIMS_STAGE:-initialize} mode=${STAGE_MODE:-stage} -> $OUT ==="
    run_workload /usr/bin/time -l -o "$OUT" Rscript -e "$WORKLOAD_CALL"
    ;;

  instruments)
    if ! command -v xctrace >/dev/null 2>&1; then
      echo "unavailable"
      echo "Warning: xctrace not found; install and select Xcode for allocation profiling." >&2
      exit 0
    fi
    echo "=== Instruments Allocations: stage=${FIMS_STAGE:-initialize} -> $OUT ==="
    # Rscript launches too quickly for Instruments to inject reliably, so R is
    # started first and xctrace attaches to its live PID. The workload waits in
    # STAGE_ATTACH_DELAY, after loading the inputs, so the recording covers the
    # stage rather than R's start-up.
    DELAY_FOR_RUN="$ATTACH_DELAY" run_workload Rscript -e "$WORKLOAD_CALL" &
    workload_pid=$!

    status="captured"
    if xctrace record --template Allocations --time-limit "$TIME_LIMIT" \
      --output "$OUT" --no-prompt --attach "$workload_pid" 2>&1 | tee "$LOG"; then
      if ! xctrace export --input "$OUT" --toc --output "${OUT%.trace}_toc.xml"; then
        status="captured-export-failed"
      fi
      if ! xctrace export --input "$OUT" \
        --xpath '/trace-toc/run[@number="1"]/tracks/track[@name="Allocations"]/details/detail[@name="Statistics"]' \
        --output "${OUT%.trace}_statistics.xml"; then
        status="captured-export-failed"
      fi
      # The allocation list, which summarize_macos.py reads to attribute
      # still-live memory to TMB/TMBad, Quadra, Rcpp or the R runtime. Without
      # this export the origins table in the report is empty.
      if ! xctrace export --input "$OUT" \
        --xpath '/trace-toc/run[@number="1"]/tracks/track[@name="Allocations"]/details/detail[@name="Allocations List"]' \
        --output "${OUT%.trace}_allocations.xml"; then
        status="captured-export-failed"
      fi
    else
      status="failed"
      echo "Warning: Instruments could not record. Check Developer Tools permissions." >&2
    fi

    workload_status=0
    wait "$workload_pid" || workload_status=$?
    if [[ "$workload_status" -ne 0 ]]; then
      echo "Error: the workload exited with status $workload_status." >&2
      exit "$workload_status"
    fi
    echo "$status"
    ;;

  *)
    echo "Error: --tool must be massif, time, or instruments (got '$TOOL')." >&2
    exit 2
    ;;
esac
