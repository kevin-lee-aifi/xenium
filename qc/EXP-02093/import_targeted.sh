#!/bin/bash

BASE_DIR="/home/workspace"
BUCKET="gs://temp-xenium-hise-transfer"

# Adjust output folder and sample ID's as needed
OUTPUT="${BASE_DIR}/xenium/qc/EXP-02093/csvs"
SAMPLES="TSS10933-004, TSS10934-005, TSS10546-032, TSS12314-001, TSS10546-027, TSS10934-003"

IFS=', ' read -r -a SAMPLE_ARRAY <<< "${SAMPLES}"

for id in "${SAMPLE_ARRAY[@]}"; do
    id="${id//[[:space:]]/}"
    gcloud storage cp "${BUCKET}/*${id}*/metrics_summary.csv" "${OUTPUT}/${id}_metric_summary.csv"
done