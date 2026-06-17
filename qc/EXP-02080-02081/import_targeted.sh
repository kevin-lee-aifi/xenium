#!/bin/bash

BASE_DIR="/home/workspace"
BUCKET="gs://temp-xenium-hise-transfer"

# Adjust output folder and sample ID's as needed
OUTPUT="${BASE_DIR}/xenium/qc/EXP-02080-02081/csvs"
SAMPLES="TSS05921-019, TSS05741-001, TSS12298-003, TSS12298-007, TSS08944-010"

IFS=', ' read -r -a SAMPLE_ARRAY <<< "${SAMPLES}"

for id in "${SAMPLE_ARRAY[@]}"; do
    id="${id//[[:space:]]/}"
    gcloud storage cp "${BUCKET}/*${id}*/metrics_summary.csv" "${OUTPUT}/${id}_metric_summary.csv"
done