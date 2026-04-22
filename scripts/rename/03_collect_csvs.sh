#!/bin/bash

# ── Configuration ────────────────────────────────────────────────────────────

# Base directory where xeniumranger rename wrote its output folders.
# Each subfolder follows the pattern: output_corrected_<TSS_ID>/
RENAMED_BASE="/home/workspace/xenium/data/renamed"

# Destination folder for all renamed CSV files.
QC_DIR="/home/workspace/xenium/qc/EXP-02059-02060/csvs"

# ── Processing ───────────────────────────────────────────────────────────────

# Create the destination directory if it doesn't already exist.
# -p also creates any missing parent directories silently.
mkdir -p "${QC_DIR}"

echo "Collecting metrics_summary.csv files from: ${RENAMED_BASE}"
echo "Destination: ${QC_DIR}"
echo ""

# Loop over every subfolder in RENAMED_BASE that matches the naming pattern.
# The glob output_corrected_* will expand to all folders produced by the
# rename script, e.g. output_corrected_TSS05029-004, output_corrected_TSS08944-007, etc.
for run_dir in "${RENAMED_BASE}"/output_corrected_*/; do

    # Guard: skip if the glob matched nothing (empty directory).
    # This prevents the loop body from running with a literal glob string.
    [ -d "${run_dir}" ] || continue

    # Extract just the folder name from the full path, e.g. "output_corrected_TSS08944-007".
    # basename strips everything up to and including the last slash.
    folder_name=$(basename "${run_dir}")

    # Derive the TSS ID by removing the "output_corrected_" prefix.
    # The # operator in bash strips the shortest matching prefix pattern.
    tss_id="${folder_name#output_corrected_}"

    # Build the full path to the metrics_summary.csv inside this run's outs/ folder.
    # xeniumranger always writes pipeline outputs into a subdirectory called outs/.
    csv_src="${run_dir}outs/metrics_summary.csv"

    # Build the destination filename using the TSS ID so each file is uniquely named.
    # Without renaming, all files would arrive as "metrics_summary.csv" and overwrite each other.
    csv_dst="${QC_DIR}/${tss_id}_metrics_summary.csv"

    echo "Processing: ${tss_id}"

    # Guard: skip if the expected CSV doesn't exist in this run folder.
    # This handles cases where xeniumranger may have failed for a sample.
    if [ ! -f "${csv_src}" ]; then
        echo "  WARNING: metrics_summary.csv not found at ${csv_src} — skipping."
        continue
    fi

    # Copy (not move) the file to the QC directory with the new TSS-based name.
    # Using cp rather than mv preserves the original output in case you need
    # to re-run or audit the full xeniumranger output later.
    cp "${csv_src}" "${csv_dst}"

    if [ $? -eq 0 ]; then
        echo "  ✓ Copied → ${csv_dst}"
    else
        echo "  ✗ Failed to copy ${csv_src}"
    fi

done

echo ""
echo "Done. All CSV files located at: ${QC_DIR}"

# Print a directory listing so you can immediately verify the results.
# ls -lh shows human-readable file sizes alongside names.
echo ""
ls -lh "${QC_DIR}"