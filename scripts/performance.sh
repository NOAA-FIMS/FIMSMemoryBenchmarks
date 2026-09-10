#!/usr/bin/env bash
# Record the CPU profile of ONE measurement.
#
# This wraps a sampling profiler around R/run_stage.R and nothing else: no
# installs, no loops, no reporting, and no timing. run_fims_benchmark() owns all
# of that. Timing is not here at all -- nothing wraps a timed run, so R launches
# those itself.
#
#   scripts/performance.sh --tool perf --lib outputs/<run>/lib/profile/main \
#     --stage initialize --out outputs/<run>/perf_main.data
#
# --tool perf          Linux perf
# --tool instruments   Instruments Time Profiler (macOS)
#
# Prints one word on stdout -- the capture status -- which the caller records.
#
# -e: exit on command failure
# -u: fail on unset variables
# -o pipefail: fail a pipeline if any command in it fails
set -euo pipefail

TOOL=""
LIB=""
STAGE="${FIMS_STAGE:-initialize}"
TEARDOWN="${TEARDOWN:-none}"
OUT=""
REPORT=""
LOG=""
N_EVAL="${FIMS_N_EVAL:-1}"
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
ATTACH_DELAY="${FIMS_INSTRUMENTS_ATTACH_DELAY:-6}"
TIME_LIMIT="${INSTRUMENTS_TIME_LIMIT:-30m}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tool) TOOL="$2"; shift 2 ;;
    --lib) LIB="$2"; shift 2 ;;
    --stage) STAGE="$2"; shift 2 ;;
    --teardown) TEARDOWN="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --report) REPORT="$2"; shift 2 ;;
    --log) LOG="$2"; shift 2 ;;
    --n-eval) N_EVAL="$2"; shift 2 ;;
    --repo-root) REPO_ROOT="$2"; shift 2 ;;
    --attach-delay) ATTACH_DELAY="$2"; shift 2 ;;
    --time-limit) TIME_LIMIT="$2"; shift 2 ;;
    *) echo "Error: unknown argument '$1'." >&2; exit 2 ;;
  esac
done

for required in TOOL LIB OUT; do
  if [[ -z "${!required}" ]]; then
    echo "Error: --${required,,} is required." >&2
    exit 2
  fi
done

WORKLOAD="$REPO_ROOT/R/run_stage.R"
[[ -f "$WORKLOAD" ]] || { echo "Error: $WORKLOAD is missing." >&2; exit 1; }
[[ -n "$LOG" ]] || LOG="${OUT}.log"
[[ -n "$REPORT" ]] || REPORT="${OUT%.data}.txt"

DELAY_FOR_RUN=0

run_workload() {
  R_LIBS="$LIB" \
    REPO_ROOT="$REPO_ROOT" \
    FIMS_STAGE="$STAGE" \
    STAGE_MODE=stage \
    TEARDOWN="$TEARDOWN" \
    FIMS_N_EVAL="$N_EVAL" \
    STAGE_ATTACH_DELAY="$DELAY_FOR_RUN" \
    "$@"
}

case "$TOOL" in
  perf)
    if ! command -v perf >/dev/null 2>&1; then
      echo "unavailable"
      echo "Warning: perf not found; install Linux perf tools for sampled CPU profiling." >&2
      exit 0
    fi
    echo "=== perf: stage=$STAGE -> $OUT ===" >&2
    # -D skips the start-up window, so the samples are the stage rather than R
    # loading packages. The workload waits the same amount before starting.
    delay_ms=$(( ATTACH_DELAY * 1000 ))
    if DELAY_FOR_RUN="$ATTACH_DELAY" run_workload \
      perf record -g -D "$delay_ms" -o "$OUT" -- Rscript "$WORKLOAD" >&2; then
      # --no-children reports self time. Without it perf reports cumulative
      # time, which ranks call-graph roots (R's evaluator) rather than the
      # functions actually running.
      perf report --stdio --no-children --sort dso,symbol -i "$OUT" > "$REPORT" 2>/dev/null
      echo "captured"
    else
      echo "failed"
      echo "Warning: perf could not record; check /proc/sys/kernel/perf_event_paranoid." >&2
    fi
    ;;

  instruments)
    if ! command -v xctrace >/dev/null 2>&1; then
      echo "unavailable"
      echo "Warning: xctrace not found; install and select Xcode for CPU profiling." >&2
      exit 0
    fi
    echo "=== Instruments Time Profiler: stage=$STAGE -> $OUT ===" >&2
    # As in memory.sh: attach to a live process, with the workload waiting after
    # the fixture is loaded so the trace covers the stage.
    DELAY_FOR_RUN="$ATTACH_DELAY" run_workload Rscript "$WORKLOAD" >&2 &
    workload_pid=$!

    status="captured"
    if xctrace record --template "Time Profiler" --time-limit "$TIME_LIMIT" \
      --output "$OUT" --no-prompt --attach "$workload_pid" 2>&1 | tee "$LOG" >&2; then
      if ! xctrace export --input "$OUT" \
        --xpath '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]' \
        --output "$REPORT" 2>/dev/null; then
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
    echo "Error: --tool must be perf or instruments (got '$TOOL')." >&2
    exit 2
    ;;
esac
