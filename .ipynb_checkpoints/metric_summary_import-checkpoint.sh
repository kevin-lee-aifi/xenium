#!/bin/bash

BASE_DIR="/home/workspace"
BUCKET="gs://temp-xenium-hise-transfer"

# Adjust output folder and sample ID's as needed
OUTPUT="${BASE_DIR}/xenium/test"
SAMPLES="TSS10931-001, TSS10931-002, TSS10932-002, TSS10546-019"

IFS=', ' read -r -a SAMPLE_ARRAY <<< "${SAMPLES}"

for id in "${SAMPLE_ARRAY[@]}"; do
    id="${id//[[:space:]]/}"
    gcloud storage cp "${BUCKET}/*${id}*/metrics_summary.csv" "${OUTPUT}/${id}_metric_summary.csv"
done