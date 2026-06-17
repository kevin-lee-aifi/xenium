#!/bin/bash

BASE_DIR="/home/workspace"
BUCKET="gs://temp-xenium-hise-transfer"

# Adjust output folder and sample ID's as needed
OUTPUT="${BASE_DIR}/xenium/qc/EXP-02080-02081/csvs"
SAMPLES="TSS12235-002, TSS12231-002, TSS10546-030, TSS12235-001, TSS12236-001, TSS12231-001, TSS12232-001, TSS10546-031"

IFS=', ' read -r -a SAMPLE_ARRAY <<< "${SAMPLES}"

for id in "${SAMPLE_ARRAY[@]}"; do
    id="${id//[[:space:]]/}"
    gcloud storage cp "${BUCKET}/*${id}*/metrics_summary.csv" "${OUTPUT}/${id}_metric_summary.csv"
done