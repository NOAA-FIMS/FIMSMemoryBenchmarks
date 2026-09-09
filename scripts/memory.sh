#!/usr/bin/env bash
# Record the memory profile of ONE measurement.
#
# This wraps a profiler around R/run_stage.R and nothing else: no installs, no
# loops, no reporting. run_fims_benchmark() in R/run_benchmark.R owns all of
# that and calls this once per ref per round, so you can also run it by hand to
# reproduce a single profile.
#
#   scripts/memory.sh --tool massif --lib outputs/<run>/lib/debug/main \
#     --stage initialize --out outputs/<run>/massif_main.out.round1
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
LIB=""
STAGE="${FIMS_STAGE:-initialize}"
STAGE_MODE="stage"
TEARDOWN="${TEARDOWN:-none}"
OUT=""
LOG=""
SIGNATURE=""
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
ATTACH_DELAY="${FIMS_INSTRUMENTS_ATTACH_DELAY:-6}"
TIME_LIMIT="${INSTRUMENTS_TIME_LIMIT:-30m}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tool) TOOL="$2"; shift 2 ;;
    --lib) LIB="$2"; shift 2 ;;
    --stage) STAGE="$2"; shift 2 ;;
    --mode) STAGE_MODE="$2"; shift 2 ;;
    --teardown) TEARDOWN="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --log) LOG="$2"; shift 2 ;;
    --signature) SIGNATURE="$2"; shift 2 ;;
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

# Every tool runs this same command, so the recordings describe the same work.
DELAY_FOR_RUN=0

run_workload() {
  R_LIBS_USER="$LIB" \
    REPO_ROOT="$REPO_ROOT" \
    FIMS_STAGE="$STAGE" \
    STAGE_MODE="$STAGE_MODE" \
    TEARDOWN="$TEARDOWN" \
    STAGE_SIGNATURE_OUT="$SIGNATURE" \
    STAGE_ATTACH_DELAY="$DELAY_FOR_RUN" \
    "$@"
}

case "$TOOL" in
  massif)
    command -v valgrind >/dev/null 2>&1 || { echo "Error: valgrind not found." >&2; exit 1; }
    echo "=== Massif: stage=$STAGE mode=$STAGE_MODE -> ${OUT}_<pid> ==="
    run_workload valgrind --tool=massif \
      --threshold=0 \
      --peak-inaccuracy=0 \
      --trace-children=yes \
      --massif-out-file="${OUT}_%p" \
      --log-file="$LOG" \
      Rscript "$WORKLOAD"
    ;;

  time)
    echo "=== /usr/bin/time -l: stage=$STAGE mode=$STAGE_MODE -> $OUT ==="
    run_workload /usr/bin/time -l -o "$OUT" Rscript "$WORKLOAD"
    ;;

  instruments)
    if ! command -v xctrace >/dev/null 2>&1; then
      echo "unavailable"
      echo "Warning: xctrace not found; install and select Xcode for allocation profiling." >&2
      exit 0
    fi
    echo "=== Instruments Allocations: stage=$STAGE -> $OUT ==="
    # Rscript launches too quickly for Instruments to inject reliably, so R is
    # started first and xctrace attaches to its live PID. The workload waits in
    # STAGE_ATTACH_DELAY, after loading the fixture, so the recording covers the
    # stage rather than R's start-up.
    DELAY_FOR_RUN="$ATTACH_DELAY" run_workload Rscript "$WORKLOAD" &
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
