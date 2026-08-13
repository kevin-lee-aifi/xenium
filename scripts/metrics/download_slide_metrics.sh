#!/bin/bash
set -euo pipefail

# Download per-slide Xenium metrics_summary.csv (and analysis_summary.html) from
# the GCS transfer bucket, into qc/<EXP_ID>/{csvs,htmls}/.
#
# Mirrors the download logic in xenium_qc_report.py:
#   - match the slide ID as a real "__"-delimited token in the output folder name
#     (avoids loose substring hits), and
#   - skip anything under the bucket's wrong_id/ folder (mis-labelled runs whose
#     slide IDs collide with real ones).
#
# Files are named "<slide_id>__<tss_id>_metric_summary.csv" to match what the
# aggregation step expects.

BASE_DIR="/home/workspace"
BUCKET="gs://temp-xenium-hise-transfer"   # fixed; edit only if the bucket changes

# ── Per-run inputs ────────────────────────────────────────────────────────────
EXP_ID="EXP-02152-02153"          # experiment ID; builds the output path
SLIDE_IDS="0097818, 0097875"      # only input for grabbing data: comma-separated

CSV_OUTPUT="${BASE_DIR}/xenium/qc/${EXP_ID}/csvs"
HTML_OUTPUT="${BASE_DIR}/xenium/qc/${EXP_ID}/htmls"
mkdir -p "${CSV_OUTPUT}" "${HTML_OUTPUT}"

# List every metrics_summary.csv in the bucket once, then filter per slide.
mapfile -t ALL_METRICS < <(gcloud storage ls "${BUCKET}/**/metrics_summary.csv")

IFS=', ' read -r -a SLIDE_ARRAY <<< "${SLIDE_IDS}"

for slide_id in "${SLIDE_ARRAY[@]}"; do
    slide_id="${slide_id//[[:space:]]/}"
    [[ -z "${slide_id}" ]] && continue
    echo "Looking for slide ${slide_id}..."
    found=0

    for uri in "${ALL_METRICS[@]}"; do
        # Skip mis-labelled runs under wrong_id/.
        [[ "${uri}" == *"/wrong_id/"* ]] && continue

        # Output folder is the parent directory name, e.g.
        # output-XETG00195__0082215__TSS10546-041__20260605__173502
        folder="$(basename "$(dirname "${uri}")")"

        # Match the slide ID as a whole "__"-delimited token.
        [[ "__${folder}__" == *"__${slide_id}__"* ]] || continue

        tss_id="$(awk -F'__' '{print $3}' <<< "${folder}")"
        [[ -z "${tss_id}" ]] && tss_id="UNKNOWN"
        prefix="${slide_id}__${tss_id}"

        gcloud storage cp "${uri}" "${CSV_OUTPUT}/${prefix}_metric_summary.csv"
        echo "  Done -> ${CSV_OUTPUT}/${prefix}_metric_summary.csv"
        found=$((found + 1))

        # analysis_summary.html sits alongside the metrics CSV.
        html_uri="$(dirname "${uri}")/analysis_summary.html"
        if gcloud storage cp "${html_uri}" "${HTML_OUTPUT}/${prefix}_analysis_summary.html" 2>/dev/null; then
            echo "  Done -> ${HTML_OUTPUT}/${prefix}_analysis_summary.html"
        else
            echo "  WARNING: No analysis_summary.html found in ${folder}"
        fi
    done

    if [[ "${found}" -eq 0 ]]; then
        echo "  ERROR: No match found for ${slide_id}"
    fi
done
