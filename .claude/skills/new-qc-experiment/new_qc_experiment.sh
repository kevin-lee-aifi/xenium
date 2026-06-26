#!/usr/bin/env bash
#
# Scaffold a new per-experiment QC folder under qc/.
#
# Usage:
#   new_qc_experiment.sh <EXP> [EXP2]
#
# Accepts one or two experiment numbers in any of these forms:
#   2093            EXP-02093             -> qc/EXP-02093/
#   2080 2081       EXP-02080 EXP-02081   -> qc/EXP-02080-02081/
#   2080-2081       "EXP-02080-02081"     -> qc/EXP-02080-02081/
#
# Numbers are zero-padded to 5 digits and joined with a hyphen, matching the
# existing folder naming convention. Each new folder gets:
#   - a csvs/ subfolder (gitignored input dir)
#   - a copy of the template xenium_qc_report.ipynb
#
set -euo pipefail

# --- locate repo root (the dir containing the template notebook) ----------
TEMPLATE_NAME="xenium_qc_report.ipynb"
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT=""
while [[ "$dir" != "/" ]]; do
  if [[ -f "$dir/$TEMPLATE_NAME" ]]; then
    REPO_ROOT="$dir"
    break
  fi
  dir="$(dirname "$dir")"
done
if [[ -z "$REPO_ROOT" ]]; then
  echo "error: could not find repo root containing $TEMPLATE_NAME" >&2
  exit 1
fi
TEMPLATE="$REPO_ROOT/$TEMPLATE_NAME"
QC_DIR="$REPO_ROOT/qc"

# --- parse args into a list of 5-digit numbers ----------------------------
if [[ $# -lt 1 ]]; then
  echo "usage: $(basename "$0") <EXP> [EXP2]" >&2
  echo "  e.g. $(basename "$0") 2093" >&2
  echo "       $(basename "$0") 2080 2081" >&2
  echo "       $(basename "$0") 2080-2081" >&2
  exit 1
fi

# Flatten args: strip EXP- prefixes, split on hyphens/spaces/commas.
raw="$*"
raw="${raw//EXP-/}"
raw="${raw//EXP/}"
raw="${raw//,/ }"
raw="${raw//-/ }"

nums=()
for tok in $raw; do
  if ! [[ "$tok" =~ ^[0-9]+$ ]]; then
    echo "error: '$tok' is not a number (expected an experiment number like 2093)" >&2
    exit 1
  fi
  # zero-pad to 5 digits
  nums+=("$(printf '%05d' "$((10#$tok))")")
done

if [[ ${#nums[@]} -gt 2 ]]; then
  echo "error: expected at most 2 experiment numbers, got ${#nums[@]}" >&2
  exit 1
fi

# --- build folder name -----------------------------------------------------
name="EXP-${nums[0]}"
if [[ ${#nums[@]} -eq 2 ]]; then
  name="EXP-${nums[0]}-${nums[1]}"
fi
target="$QC_DIR/$name"

if [[ -e "$target" ]]; then
  echo "error: $target already exists; refusing to overwrite" >&2
  exit 1
fi

# --- scaffold --------------------------------------------------------------
mkdir -p "$target/csvs"
cp "$TEMPLATE" "$target/$TEMPLATE_NAME"

echo "Created $target"
echo "  - csvs/                (gitignored input dir)"
echo "  - $TEMPLATE_NAME       (copied from template)"
