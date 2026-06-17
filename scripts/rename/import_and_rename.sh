#!/bin/bash
#
# Fetch a sample's full xenium bundle from the bucket, then run
# `xeniumranger rename` on it.

# This script uses `exit` for error handling. If you `source` it, those exits
# run in your interactive shell and close your terminal. Guard against that:
# when sourced, re-run as a subprocess so exits stay contained, then hand the
# exit code back to your shell.
if [ "${BASH_SOURCE[0]}" != "${0}" ]; then
    bash "${BASH_SOURCE[0]}" "$@"
    return $?
fi

# ── Edit these ─────────────────────────────────────────────────────────────

INCORRECT_SAMPLE="TSS10546-041"   # current (wrong) sample ID in the bucket
CORRECT_SAMPLE="TSS10546-042"     # correct sample ID -> used as region name
CORRECT_EXPERIMENT="EXP-02140"    # correct cassette / experiment name
SLIDE_ID="0082215"                # only to pick between duplicate runs; "" if unique

BUCKET="gs://temp-xenium-hise-transfer"
BUNDLE_BASE="/home/workspace/xenium/data/bundles"   # download goes here
OUTPUT_BASE="/home/workspace/xenium/data/renamed"   # corrected bundle goes here
XENIUMRANGER_BIN="/home/workspace/xeniumranger-xenium4.0/xeniumranger"

WRONG_ID_PREFIX="wrong_id"   # bucket subfolder the incorrect folder is moved into

# ── Processing ───────────────────────────────────────────────────────────────

if [ ! -x "${XENIUMRANGER_BIN}" ]; then
    echo "ERROR: xeniumranger not found/executable at ${XENIUMRANGER_BIN}"
    exit 1
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

# Final folder name mirrors the source bucket folder, but with the incorrect
# sample ID swapped for the correct one (e.g.
#   output-XETG00123__0097818__TSS12577-002__20260612__193747
# → output-XETG00123__0097818__TSS12576-002__20260612__193747).
SRC_NAME="$(basename "${SRC_DIR%/}")"
FINAL_NAME="${SRC_NAME//${INCORRECT_SAMPLE}/${CORRECT_SAMPLE}}"
FINAL_PATH="${OUTPUT_BASE}/${FINAL_NAME}"

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
RENAME_RC=$?

# Promote the `outs` folder out of the parent run folder and delete the rest.
if [ ${RENAME_RC} -eq 0 ]; then
    RUN_PATH="${OUTPUT_BASE}/${RUN_ID}"
    OUTS_PATH="${RUN_PATH}/outs"

    if [ -e "${FINAL_PATH}" ]; then
        echo "✗ destination already exists: ${FINAL_PATH}"
        echo "  Leaving ${RUN_PATH} in place; remove the destination and re-run."
        exit 1
    fi

    echo "Promoting outs → ${FINAL_PATH}"
    mv "${OUTS_PATH}" "${FINAL_PATH}" \
        || { echo "ERROR: failed to move outs folder — leaving ${RUN_PATH} in place."; exit 1; }

    rm -rf "${RUN_PATH}"

    echo "✓ Success → ${FINAL_PATH}"

    # ── Push to bucket ───────────────────────────────────────────────────────
    # 1. Upload the corrected folder to the bucket root.
    # 2. Move the original (incorrect) folder into ${WRONG_ID_PREFIX}/ so it's
    #    out of the way but not destroyed.
    DEST_CORRECTED="${BUCKET}/${FINAL_NAME}"
    DEST_WRONG="${BUCKET}/${WRONG_ID_PREFIX}/${SRC_NAME}"

    echo
    echo "Bucket changes to apply:"
    echo "  upload  ${FINAL_PATH}/  →  ${DEST_CORRECTED}/"
    echo "  move    ${SRC_DIR%/}/   →  ${DEST_WRONG}/"

    # Always confirm before mutating the shared bucket.
    read -r -p "Proceed with these bucket changes? [y/N] " REPLY
    case "${REPLY}" in
        [yY]|[yY][eE][sS]) ;;
        *) echo "Skipped bucket changes. Local result kept at ${FINAL_PATH}."; exit 0 ;;
    esac

    # Upload the corrected folder first, so the original is only moved once
    # the good data is safely in the bucket.
    echo "Uploading corrected bundle → ${DEST_CORRECTED}/"
    gcloud storage rsync -r "${FINAL_PATH}" "${DEST_CORRECTED}/" \
        || { echo "ERROR: upload failed — original folder left in place."; exit 1; }

    echo "Moving incorrect folder → ${DEST_WRONG}/"
    gcloud storage mv "${SRC_DIR%/}" "${DEST_WRONG}" \
        || { echo "ERROR: move of incorrect folder failed — review bucket manually."; exit 1; }

    echo "✓ Bucket updated."

    echo "Removing input bundle: ${BUNDLE_PATH}"
    rm -rf "${BUNDLE_PATH}"
else
    echo "✗ rename FAILED for ${INCORRECT_SAMPLE}"
    echo "  Input bundle kept at ${BUNDLE_PATH} for retry."
fi
