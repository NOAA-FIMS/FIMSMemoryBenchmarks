#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)_$$"
OUTPUT_DIR="$REPO_ROOT/outputs/$RUN_ID"
mkdir -p "$OUTPUT_DIR"
cd "$REPO_ROOT"

# Set these in the environment to compare different branches without editing.
REF_FIRST="${REF_FIRST:-main}"
REF_COMPARE="${REF_COMPARE:-xptr-refactor}"
SUMMARY_ARGS=()
CPU_SUMMARY_ARGS=()
HOST_OS="$(uname -s)"

run_ref() {
  local ref="$1"
  local base_out_file="$2"

  echo "=== Installing FIMS branch: $ref ==="
  FIMS_REF="$ref" Rscript -e "source(file.path('R', 'setup_FIMS.R')); install_fims_debug(Sys.getenv('FIMS_REF'))"

  local fims_version
  fims_version=$(Rscript -e "cat(as.character(packageVersion('FIMS')))")

  local ref_safe="${ref//[^A-Za-z0-9._-]/_}"
  if [[ "$HOST_OS" == "Darwin" ]]; then
    local native_out="$OUTPUT_DIR/macos_profile_${ref_safe}_${fims_version}.txt"
    local trace_out="$OUTPUT_DIR/instruments_allocations_${ref_safe}_${fims_version}.trace"
    local trace_toc="$OUTPUT_DIR/instruments_allocations_${ref_safe}_${fims_version}_toc.xml"
    local trace_stats="$OUTPUT_DIR/instruments_allocations_${ref_safe}_${fims_version}_statistics.xml"
    local trace_log="$OUTPUT_DIR/instruments_allocations_${ref_safe}_${fims_version}.log"
    local trace_status="not-requested"
    local cpu_trace="$OUTPUT_DIR/instruments_cpu_${ref_safe}_${fims_version}.trace"
    local cpu_xml="$OUTPUT_DIR/instruments_cpu_${ref_safe}_${fims_version}.xml"
    local cpu_log="$OUTPUT_DIR/instruments_cpu_${ref_safe}_${fims_version}.log"
    local cpu_status="not-requested"

    if [[ "${MACOS_INSTRUMENTS:-1}" == "1" ]] && command -v xctrace >/dev/null 2>&1; then
      echo "=== Running Instruments Allocations -> $trace_out ==="
      # Rscript launches too quickly for Instruments to inject reliably. Start R
      # first, pause before the benchmark, and attach xctrace to its live PID.
      REPO_ROOT="$REPO_ROOT" \
        FIMS_INSTRUMENTS_ATTACH_DELAY="${FIMS_INSTRUMENTS_ATTACH_DELAY:-6}" \
        Rscript -e \
        "Sys.sleep(as.numeric(Sys.getenv('FIMS_INSTRUMENTS_ATTACH_DELAY'))); source(file.path(Sys.getenv('REPO_ROOT'), 'R', 'setup_FIMS.R')); setup_fims_model(mode = 'inner'); quit(save='no', status=0)" &
      local r_pid=$!

      if xctrace record \
        --template Allocations \
        --time-limit "${INSTRUMENTS_TIME_LIMIT:-30m}" \
        --output "$trace_out" \
        --no-prompt \
        --attach "$r_pid" 2>&1 | tee "$trace_log"; then
        trace_status="captured"
        if ! xctrace export --input "$trace_out" --toc --output "$trace_toc"; then
          trace_status="captured-export-failed"
          echo "Warning: Instruments trace was captured, but its table of contents could not be exported." >&2
        fi
        if ! xctrace export \
          --input "$trace_out" \
          --xpath '/trace-toc/run[@number="1"]/tracks/track[@name="Allocations"]/details/detail[@name="Statistics"]' \
          --output "$trace_stats"; then
          trace_status="captured-export-failed"
          echo "Warning: Instruments trace was captured, but allocation statistics could not be exported." >&2
        fi
      else
        trace_status="failed"
        echo "Warning: Instruments could not profile '$ref'. Check macOS Developer Tools permissions; continuing with /usr/bin/time -l." >&2
      fi

      local r_status=0
      if wait "$r_pid"; then
        :
      else
        r_status=$?
      fi
      if [[ "$r_status" -ne 0 ]]; then
        echo "Error: the FIMS model exited with status $r_status during Instruments profiling." >&2
        return "$r_status"
      fi
    elif [[ "${MACOS_INSTRUMENTS:-1}" == "1" ]]; then
      trace_status="unavailable"
      echo "Warning: xctrace is unavailable; install and select Xcode to enable detailed allocation profiling." >&2
    else
      trace_status="disabled"
    fi

    if [[ "${CPU_PROFILE:-1}" == "1" ]] && command -v xctrace >/dev/null 2>&1; then
      echo "=== Running Instruments Time Profiler -> $cpu_trace ==="
      REPO_ROOT="$REPO_ROOT" \
        FIMS_INSTRUMENTS_ATTACH_DELAY="${FIMS_INSTRUMENTS_ATTACH_DELAY:-6}" \
        Rscript -e \
        "Sys.sleep(as.numeric(Sys.getenv('FIMS_INSTRUMENTS_ATTACH_DELAY'))); source(file.path(Sys.getenv('REPO_ROOT'), 'R', 'setup_FIMS.R')); setup_fims_model(mode = 'inner'); quit(save='no', status=0)" &
      local cpu_pid=$!
      if xctrace record --template "Time Profiler" \
        --time-limit "${INSTRUMENTS_TIME_LIMIT:-30m}" \
        --output "$cpu_trace" --no-prompt --attach "$cpu_pid" 2>&1 | tee "$cpu_log"; then
        cpu_status="captured"
        if ! xctrace export --input "$cpu_trace" \
          --xpath '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]' \
          --output "$cpu_xml"; then
          cpu_status="captured-export-failed"
        fi
      else
        cpu_status="failed"
      fi
      local cpu_r_status=0
      wait "$cpu_pid" || cpu_r_status=$?
      [[ "$cpu_r_status" -eq 0 ]] || return "$cpu_r_status"
    elif [[ "${CPU_PROFILE:-1}" == "1" ]]; then
      cpu_status="unavailable"
    else
      cpu_status="disabled"
    fi
    CPU_SUMMARY_ARGS+=(--run "$ref" "$fims_version" "$cpu_status" "$cpu_xml")

    echo "=== Running macOS native memory profile -> $native_out ==="
    REPO_ROOT="$REPO_ROOT" /usr/bin/time -l -o "$native_out" \
      Rscript -e "source(file.path(Sys.getenv('REPO_ROOT'), 'R', 'setup_FIMS.R')); setup_fims_model(mode = 'inner'); quit(save='no', status=0)"
    SUMMARY_ARGS+=(--run "$ref" "$fims_version" "$native_out" "$trace_status" "$trace_out")
  else
    local final_out="${base_out_file}_${ref_safe}_${fims_version}.out"
    local log_file="$OUTPUT_DIR/valgrind_${ref_safe}_${fims_version}.log"
    echo "=== Running Valgrind Massif -> ${final_out}.<pid> ==="
    REPO_ROOT="$REPO_ROOT" valgrind --tool=massif \
      --threshold=0 \
      --trace-children=yes \
      --massif-out-file="${final_out}.%p" \
      --log-file="$log_file" \
      Rscript -e "source(file.path(Sys.getenv('REPO_ROOT'), 'R', 'setup_FIMS.R')); setup_fims_model(mode = 'inner'); quit(save='no', status=0)"
    SUMMARY_ARGS+=(--run "$ref" "$fims_version" "$final_out")

    local perf_data="$OUTPUT_DIR/perf_${ref_safe}_${fims_version}.data"
    local perf_report="$OUTPUT_DIR/perf_${ref_safe}_${fims_version}.txt"
    local cpu_status="not-requested"
    if [[ "${CPU_PROFILE:-1}" == "1" ]] && command -v perf >/dev/null 2>&1; then
      echo "=== Running Linux perf CPU profiler -> $perf_data ==="
      if REPO_ROOT="$REPO_ROOT" perf record -g -o "$perf_data" -- \
        Rscript -e "source(file.path(Sys.getenv('REPO_ROOT'), 'R', 'setup_FIMS.R')); setup_fims_model(mode = 'inner'); quit(save='no', status=0)"; then
        cpu_status="captured"
        perf report --stdio --sort comm,dso,symbol -i "$perf_data" > "$perf_report"
      else
        cpu_status="failed"
      fi
    elif [[ "${CPU_PROFILE:-1}" == "1" ]]; then
      cpu_status="unavailable"
      echo "Warning: perf is unavailable; install Linux perf tools for sampled CPU profiling." >&2
    else
      cpu_status="disabled"
    fi
    CPU_SUMMARY_ARGS+=(--run "$ref" "$fims_version" "$cpu_status" "$perf_report")
  fi
}

run_ref "$REF_FIRST" "$OUTPUT_DIR/valgrind_massif"

if [[ "$REF_FIRST" == "$REF_COMPARE" ]]; then
  echo "Warning: both refs are '$REF_FIRST'; skipping the duplicate run." >&2
else
  run_ref "$REF_COMPARE" "$OUTPUT_DIR/valgrind_massif"
fi

CPU_REPORT_FILE="$OUTPUT_DIR/cpu_profile_report.md"
python3 "$REPO_ROOT/scripts/summarize_cpu.py" \
  --platform "$HOST_OS" "${CPU_SUMMARY_ARGS[@]}" --output "$CPU_REPORT_FILE"

if [[ "$HOST_OS" == "Darwin" ]]; then
  REPORT_FILE="$OUTPUT_DIR/macos_memory_report.md"
  python3 "$REPO_ROOT/scripts/summarize_macos.py" "${SUMMARY_ARGS[@]}" --output "$REPORT_FILE"
else
  REPORT_FILE="$OUTPUT_DIR/valgrind_massif_report.md"
  python3 "$REPO_ROOT/scripts/summarize_massif.py" "${SUMMARY_ARGS[@]}" --output "$REPORT_FILE"
fi

echo "======================================"
echo "Memory profile outputs written to $OUTPUT_DIR"
echo "Markdown summary: $REPORT_FILE"
echo "CPU summary: $CPU_REPORT_FILE"
