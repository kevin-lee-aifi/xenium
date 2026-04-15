#!/bin/bash

# --- Configuration ---
BASE_DIR="/home/workspace"
BUCKET="gs://temp-xenium-hise-transfer"
OUTPUT="${BASE_DIR}/xenium/2026_metric_summaries"

# Ensure the local output directory exists before writing any files into it.
# The -p flag suppresses errors if it already exists and creates parent dirs.
mkdir -p "${OUTPUT}"

# --- Main Loop ---
# `gcloud storage ls` returns lines like: gs://bucket-name/folder_name/
# We use a `while read` loop instead of `for` because `while read` processes
# one line at a time, safely handling any whitespace in paths.
# `IFS=` prevents leading/trailing whitespace from being stripped.
# `-r` prevents backslash interpretation.
# Process substitution `< <(...)` feeds the command output as a file stream.
while IFS= read -r content; do

    # Step 1: Strip the trailing slash, then extract just the last path component.
    # `${content%/}` is parameter expansion — it removes the trailing `/`.
    # `basename` then returns only the final segment (e.g., "sample_2026_run1").
    folder=$(basename "${content%/}")

    # Step 2: Skip blank lines or the bucket root itself (edge cases from `ls`).
    [[ -z "${folder}" ]] && continue

    # Step 3: Pattern match using double-bracket [[ ]] — the only Bash construct
    # that supports glob wildcards like * in conditional expressions.
    # This checks if the folder name contains the substring "_2026" anywhere.
    if [[ "${folder}" == *"_2026"* ]]; then
        echo "Found matching folder: ${folder}"

        # Step 4: Copy the metrics_summary.csv from the matched GCS folder
        # to a locally named file that includes the folder name for traceability.
        # If metrics_summary.csv is nested deeper, change to: "${BUCKET}/${folder}/**/metrics_summary.csv"
        gcloud storage cp \
            "${BUCKET}/${folder}/metrics_summary.csv" \
            "${OUTPUT}/${folder}_metric_summary.csv"
    fi

done < <(gcloud storage ls "${BUCKET}/")