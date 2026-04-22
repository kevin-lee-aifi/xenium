#!/bin/bash

# ── Configuration ────────────────────────────────────────────────────────────

BUNDLE_BASE="/home/workspace/xenium/data/bundles"
OUTPUT_BASE="/home/workspace/xenium/data/renamed"

# Swap definitions: "OLD_TSS_ID:NEW_TSS_ID:NEW_EXP_ID"
# EXP-02059 belongs to Slide 1 (cassette 0077730)
# EXP-02060 belongs to Slide 2 (cassette 0077738)
# After swapping: Slide 1 samples receive EXP-02060, Slide 2 samples receive EXP-02059
SWAPS=(
    "TSS05029-004:TSS05029-005:EXP-02060"   # Slide1 A1 → gets Slide2 EXP ID
    "TSS05029-005:TSS05029-004:EXP-02059"   # Slide2 A1 → gets Slide1 EXP ID
    "TSS06403-004:TSS06403-005:EXP-02060"   # Slide1 A2 → gets Slide2 EXP ID
    "TSS06403-005:TSS06403-004:EXP-02059"   # Slide2 A2 → gets Slide1 EXP ID
    "TSS08944-007:TSS08944-008:EXP-02060"   # Slide1 A3 → gets Slide2 EXP ID
    "TSS08944-008:TSS08944-007:EXP-02059"   # Slide2 A3 → gets Slide1 EXP ID
)

# ── Processing ───────────────────────────────────────────────────────────────

mkdir -p "${OUTPUT_BASE}"

# cd into OUTPUT_BASE so xeniumranger writes output here.
# xeniumranger has no --output-dir flag; it always writes to the current directory.
cd "${OUTPUT_BASE}" || { echo "ERROR: Cannot cd to ${OUTPUT_BASE}"; exit 1; }

for swap in "${SWAPS[@]}"; do

    # Split each colon-delimited entry into its three components.
    IFS=':' read -r OLD_ID NEW_ID NEW_EXP <<< "${swap}"

    # Append the new TSS ID to "output_corrected" to ensure each sample
    # gets a unique output folder. Using a bare "output_corrected" for all
    # 6 samples would cause every run to overwrite the same folder.
    RUN_ID="output_corrected_${NEW_ID}"

    BUNDLE_PATH="${BUNDLE_BASE}/${OLD_ID}"

    echo "──────────────────────────────────────────"
    echo "Renaming:  ${OLD_ID}"
    echo "  → Run ID (--id):      ${RUN_ID}"
    echo "  → New region name:    ${NEW_ID}"
    echo "  → New cassette name:  ${NEW_EXP}"
    echo "  → Bundle path:        ${BUNDLE_PATH}"

    # Guard: skip if the expected bundle folder doesn't exist.
    if [ ! -d "${BUNDLE_PATH}" ]; then
        echo "  ERROR: Bundle folder not found at ${BUNDLE_PATH} — skipping."
        continue
    fi

    xeniumranger rename \
        --id="${RUN_ID}" \
        --xenium-bundle="${BUNDLE_PATH}" \
        --region-name="${NEW_ID}" \
        --cassette-name="${NEW_EXP}"

    EXIT_CODE=$?

    if [ ${EXIT_CODE} -eq 0 ]; then
        echo "  ✓ Success → ${OUTPUT_BASE}/${RUN_ID}"
    else
        echo "  ✗ xeniumranger rename FAILED for ${OLD_ID} (exit code ${EXIT_CODE})"
    fi

done

echo ""
echo "All rename operations complete."
echo "Output located at: ${OUTPUT_BASE}"