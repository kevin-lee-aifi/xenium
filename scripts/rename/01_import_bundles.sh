#!/bin/bash

# ── Configuration ────────────────────────────────────────────────────────────

BASE_DIR="/home/workspace"
BUCKET="gs://temp-xenium-hise-transfer"
OUTPUT="${BASE_DIR}/xenium/data/bundles"
SAMPLES="TSS05029-004, TSS06403-004, TSS08944-007, TSS05029-005, TSS06403-005, TSS08944-008"

# List of files xeniumranger rename requires as part of the xenium bundle.
# Extend this array if your pipeline needs additional files.
FILES_TO_FETCH=(
    "experiment.xenium"
    "metrics_summary.csv"
    "analysis_summary.html"
)

# ── Processing ───────────────────────────────────────────────────────────────

# Splits the comma-separated SAMPLES string into a proper bash array.
# IFS=', ' tells bash to treat commas AND spaces as delimiters.
IFS=', ' read -r -a SAMPLE_ARRAY <<< "${SAMPLES}"

for id in "${SAMPLE_ARRAY[@]}"; do

    # Strip any residual whitespace from the sample ID (e.g. leading/trailing spaces).
    id="${id//[[:space:]]/}"

    # Define a dedicated output folder for this sample.
    # Each sample gets its own subdirectory: e.g. .../test/TSS10937-002/
    SAMPLE_DIR="${OUTPUT}/${id}"

    # Create the sample directory (-p suppresses errors if it already exists
    # and also creates any missing parent directories).
    mkdir -p "${SAMPLE_DIR}"

    echo "Processing sample: ${id}"

    # Loop over every file we want to fetch for this sample.
    for file in "${FILES_TO_FETCH[@]}"; do

        echo "  Fetching: ${file}"

        # Use a glob pattern to match the sample's folder in the bucket
        # (we don't know the exact bucket subfolder name, only that it
        # contains the sample ID), then copy the target file into the
        # local per-sample directory.
        # The destination keeps the original filename intact.
        gcloud storage cp \
            "${BUCKET}/*${id}*/${file}" \
            "${SAMPLE_DIR}/${file}"

        # Check whether the last command succeeded (exit code 0 = success).
        # This lets you see immediately which files failed rather than
        # finding out only at the xeniumranger step.
        if [ $? -ne 0 ]; then
            echo "  WARNING: Failed to fetch ${file} for sample ${id}"
        fi

    done

    echo "  Done → ${SAMPLE_DIR}"
    echo ""

done