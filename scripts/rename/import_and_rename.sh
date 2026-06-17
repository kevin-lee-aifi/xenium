#!/bin/bash
#
# Fetch a sample's full xenium bundle from the bucket, then run
# `xeniumranger rename` on it.

# ── Edit these ─────────────────────────────────────────────────────────────

INCORRECT_SAMPLE="TSS12577-002"   # current (wrong) sample ID in the bucket
CORRECT_SAMPLE="TSS12576-002"     # correct sample ID -> used as region name
CORRECT_EXPERIMENT="EXP-02152"    # correct cassette / experiment name
SLIDE_ID="0097818"                # only to pick between duplicate runs; "" if unique

BUCKET="gs://temp-xenium-hise-transfer"
BUNDLE_BASE="/home/workspace/xenium/data/bundles"   # download goes here
OUTPUT_BASE="/home/workspace/xenium/data/renamed"   # corrected bundle goes here
XENIUMRANGER_BIN="/home/workspace/xeniumranger-xenium4.0/xeniumranger"

# ── Processing ───────────────────────────────────────────────────────────────

if [ ! -x "${XENIUMRANGER_BIN}" ]; then
    echo "ERROR: xeniumranger not found/executable at ${XENIUMRANGER_BIN}"
    return 1 2>/dev/null || exit 1
fi

mkdir -p "${BUNDLE_BASE}" "${OUTPUT_BASE}"

echo "Sample: ${INCORRECT_SAMPLE}${SLIDE_ID:+ (slide ${SLIDE_ID})}"

# Find the bucket folder matching the sample ID (and slide ID, if given).
mapfile -t MATCHES < <(
    gcloud storage ls "${BUCKET}/" 2>/dev/null | grep '/$' \
        | grep -F "${INCORRECT_SAMPLE}" | grep -F "${SLIDE_ID}"
)

if [ "${#MATCHES[@]}" -eq 0 ]; then
    echo "ERROR: no bucket folder matched ${INCORRECT_SAMPLE}."
    exit 1
fi
if [ "${#MATCHES[@]}" -gt 1 ]; then
    echo "ERROR: ${#MATCHES[@]} folders matched — set SLIDE_ID to disambiguate:"
    printf '  %s\n' "${MATCHES[@]}"
    exit 1
fi
SRC_DIR="${MATCHES[0]}"
echo "Source: ${SRC_DIR}"

# Include the slide ID in the folder name so duplicate runs stay separate.
BUNDLE_PATH="${BUNDLE_BASE}/${INCORRECT_SAMPLE}${SLIDE_ID:+_${SLIDE_ID}}"
mkdir -p "${BUNDLE_PATH}"

# Download the whole bundle. rsync resumes if interrupted; bundles are large.
echo "Syncing full bundle from ${SRC_DIR}"
gcloud storage rsync -r "${SRC_DIR}" "${BUNDLE_PATH}/" \
    || { echo "ERROR: failed to sync bundle — aborting."; exit 1; }

# Unique run folder so repeat runs don't overwrite each other.
RUN_ID="output_corrected_${CORRECT_SAMPLE}"
echo "Renaming → ${RUN_ID} (region ${CORRECT_SAMPLE}, cassette ${CORRECT_EXPERIMENT})"

# xeniumranger writes to the current dir; cd in a subshell so it doesn't leak.
(
    cd "${OUTPUT_BASE}" || exit 1
    "${XENIUMRANGER_BIN}" rename \
        --id="${RUN_ID}" \
        --xenium-bundle="${BUNDLE_PATH}" \
        --region-name="${CORRECT_SAMPLE}" \
        --cassette-name="${CORRECT_EXPERIMENT}"
)

# Delete the download only if the rename succeeded.
if [ $? -eq 0 ]; then
    echo "✓ Success → ${OUTPUT_BASE}/${RUN_ID}"
    echo "Removing input bundle: ${BUNDLE_PATH}"
    # rm -rf "${BUNDLE_PATH}"
else
    echo "✗ rename FAILED for ${INCORRECT_SAMPLE}"
    echo "  Input bundle kept at ${BUNDLE_PATH} for retry."
fi
