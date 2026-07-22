#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="$REPO_ROOT/outputs"

mkdir -p "$OUTPUT_DIR"

run_ref() {
  local ref="$1"
  local out_file="$2"

  valgrind --tool=massif \
    --massif-out-file="$out_file" \
    Rscript -e "source('R/install_FIMS_debug'); install_fims_debug('$ref'); source('R/run_benchmark.R')"
}

run_ref "main" "$OUTPUT_DIR/massif_main.out"
run_ref "xptr-refactor" "$OUTPUT_DIR/massif_xptr.out"

echo "Massif outputs written to $OUTPUT_DIR"
echo "  - $OUTPUT_DIR/massif_main.out"
echo "  - $OUTPUT_DIR/massif_xptr.out"
