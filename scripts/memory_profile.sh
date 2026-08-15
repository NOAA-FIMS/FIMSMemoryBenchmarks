#!/usr/bin/env bash
# make failures strict:
# -e: exit on command failure
# -u: fail on unset variables
# -o pipefail: fail pipeline if any command fails 
set -eo pipefail

# set output directory
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="$REPO_ROOT/outputs"
mkdir -p "$OUTPUT_DIR"

# set benchmark branches (ref)
REF_FIRST="main"
REF_COMPARE="main" #"xptr-refactor"


# function that runs valgrind on one branch
run_ref() {
  # git branch to test (1st argument)
  local ref="$1" 
  # massif output file path (2nd argument)
  local base_out_file="$2"

  echo "=== Installing FIMS branch: $ref ==="

  # compile cleanly outside Valgrind
  Rscript -e "source(file.path('R', 'setup_FIMS.R')); install_fims_debug('$ref')"
  
  # get the installed FIMS version
  local fims_version
  fims_version=$(Rscript -e "cat(as.character(packageVersion('FIMS')))")
  
  # clean the Git ref name for a path-safe filename
  local ref_safe="${ref//[^A-Za-z0-9._-]/_}"
  
  # construct the final output file name
  local final_out="${base_out_file}_${ref_safe}_${fims_version}.out"

  echo "=== Running Valgrind Massif -> $final_out ==="

  # massif tool profiles heap usage
  REPO_ROOT="$REPO_ROOT" valgrind --tool=massif \
    --threshold=0\
    --trace-children=yes \
    --massif-out-file="${final_out}.%p" \
    --log-file="massif_report.txt" \
    Rscript -e "source(file.path(Sys.getenv('REPO_ROOT'), 'R', 'setup_FIMS.R')); setup_fims_model(mode = 'inner'); quit(save='no', status=0)"

}

# Run valgrind on first branch
run_ref "$REF_FIRST" "$OUTPUT_DIR/valgrind_massif" "FIRST_OUT_FILE"

if [[ "$REF_FIRST" == "$REF_COMPARE" ]]; then
    echo "Warning: REF_FIRST and REF_COMPARE are both '$REF_FIRST'; skipping duplicate Valgrind run." >&2
else
    run_ref "$REF_COMPARE" "$OUTPUT_DIR/valgrind_massif" "COMPARE_OUT_FILE"
fi

echo "======================================"
echo "Massif outputs written to $OUTPUT_DIR"
echo " - $FIRST_OUT_FILE"
if [[ -n "$COMPARE_OUT_FILE" ]]; then
    echo " - $COMPARE_OUT_FILE"
fi
