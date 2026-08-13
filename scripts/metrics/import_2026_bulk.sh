#!/bin/bash
set -euo pipefail

# Bulk-download metrics_summary.csv files from GCS for runs between
# April 1 2026 and July 31 2026 (folder date token: 20260401–20260731).
# Skips wrong_id/ folders. Output files are named <folder>_metric_summary.csv.

BUCKET="gs://temp-xenium-hise-transfer"
OUTPUT="/home/workspace/xenium/data/2026_metric_summaries"
DATE_MIN=20260401
DATE_MAX=20260731

mkdir -p "${OUTPUT}"

echo "Listing all metrics_summary.csv files in bucket..."
mapfile -t ALL_METRICS < <(gcloud storage ls "${BUCKET}/**/metrics_summary.csv")
echo "Found ${#ALL_METRICS[@]} total CSV(s). Filtering by date range..."

count=0
for uri in "${ALL_METRICS[@]}"; do
    [[ "${uri}" == *"/wrong_id/"* ]] && continue

    folder="$(basename "$(dirname "${uri}")")"

    # Date is the 4th double-underscore-delimited token (e.g. 20260605).
    date_token="$(awk -F'__' '{print $4}' <<< "${folder}")"
    [[ -z "${date_token}" ]] && continue
    [[ "${date_token}" =~ ^[0-9]{8}$ ]] || continue

    if (( date_token >= DATE_MIN && date_token <= DATE_MAX )); then
        dest="${OUTPUT}/${folder}_metric_summary.csv"
        gcloud storage cp "${uri}" "${dest}"
        echo "  Saved -> ${dest}"
        count=$((count + 1))
    fi
done

echo "Done. Downloaded ${count} file(s) to ${OUTPUT}."
