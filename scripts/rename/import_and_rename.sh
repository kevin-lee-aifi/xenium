#!/bin/bash
#
# Fetch each sample's xenium bundle from the bucket and run `xeniumranger
# rename`. Validates every row and confirms once up front, then processes each
# sample; a failure skips to the next and is reported in the final summary.

# When sourced, re-run as a subprocess so our `exit`s don't close your shell.
if [ "${BASH_SOURCE[0]}" != "${0}" ]; then
    bash "${BASH_SOURCE[0]}" "$@"
    return $?
fi

# ── Edit these ─────────────────────────────────────────────────────────────
# One line per sample: "INCORRECT_SAMPLE, INCORRECT_SLIDE, CORRECT_SAMPLE, CORRECT_SLIDE"
# The incorrect sample+slide locate the source folder; the correct sample+slide
# are rewritten into the output folder name. Use the same slide twice if only
# the sample ID is wrong.
SAMPLES=(
    "TSS10546-041, 0082205, TSS10546-042, 0082215"
)

BUCKET="gs://temp-xenium-hise-transfer"
BUNDLE_BASE="/home/workspace/xenium/data/bundles"   # download goes here
OUTPUT_BASE="/home/workspace/xenium/data/renamed"   # corrected bundle goes here
XENIUMRANGER_BIN="/home/workspace/xeniumranger-xenium4.0/xeniumranger"
WRONG_ID_PREFIX="wrong_id"   # bucket subfolder the incorrect folder is moved into

# ── Helpers ──────────────────────────────────────────────────────────────────

trim() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "${s}"
}

# Folder-name-safe value check. 64 is xeniumranger's --region-name limit; all
# of these also end up in folder/bucket paths, so the charset rule applies too.
validate_name() {
    local label="$1" value="$2"
    if (( ${#value} > 64 )) || [[ ! "${value}" =~ ^[A-Za-z0-9_-]+$ ]]; then
        echo "ERROR: ${label} must be <= 64 chars and use only letters, numbers, '_' and '-': '${value}'"
        exit 1
    fi
}

# ── Pre-flight checks ──────────────────────────────────────────────────────

if [ ! -x "${XENIUMRANGER_BIN}" ]; then
    echo "ERROR: xeniumranger not found/executable at ${XENIUMRANGER_BIN}"
    exit 1
fi
if ! command -v gcloud >/dev/null 2>&1; then
    echo "ERROR: gcloud not found in PATH"
    exit 1
fi
if [ "${#SAMPLES[@]}" -eq 0 ]; then
    echo "ERROR: no samples listed in SAMPLES."
    exit 1
fi

mkdir -p "${BUNDLE_BASE}" "${OUTPUT_BASE}"

if ! BUCKET_LIST="$(gcloud storage ls "${BUCKET}/")"; then
    echo "ERROR: failed to list bucket root: ${BUCKET}/"
    exit 1
fi

# ── Phase 1: validate and resolve every row (any error aborts the batch) ────

R_INCSAMPLE=(); R_INCSLIDE=(); R_CORSAMPLE=(); R_CORSLIDE=()
R_SRCDIR=(); R_SRCNAME=(); R_FINALNAME=(); R_FINALPATH=(); R_BUNDLEPATH=()
R_DESTCORR=(); R_DESTWRONG=()

echo "Validating ${#SAMPLES[@]} sample(s)…"

for row in "${SAMPLES[@]}"; do
    [[ -z "$(trim "${row}")" ]] && continue

    IFS=',' read -r f1 f2 f3 f4 <<< "${row}"
    incsample="$(trim "${f1}")"
    incslide="$(trim "${f2}")"
    corsample="$(trim "${f3}")"
    corslide="$(trim "${f4}")"

    if [[ -z "${incsample}" || -z "${incslide}" || -z "${corsample}" || -z "${corslide}" ]]; then
        echo "ERROR: row needs all four fields (incorrect sample, incorrect slide, correct sample, correct slide): '${row}'"
        exit 1
    fi

    validate_name "incorrect sample (row '${row}')" "${incsample}"
    validate_name "incorrect slide (row '${row}')"  "${incslide}"
    validate_name "correct sample (row '${row}')"   "${corsample}"
    validate_name "correct slide (row '${row}')"    "${corslide}"

    # Match the source folder by both incorrect IDs as delimited fields (__ID__).
    matches=()
    while IFS= read -r url; do
        [[ "${url}" == */ ]] || continue
        name="$(basename "${url%/}")"
        [[ "${name}" == *"__${incsample}__"* ]] || continue
        [[ "${name}" == *"__${incslide}__"*  ]] || continue
        matches+=("${url}")
    done <<< "${BUCKET_LIST}"

    if [ "${#matches[@]}" -eq 0 ]; then
        echo "ERROR: no bucket folder matched sample ${incsample} / slide ${incslide}."
        exit 1
    fi
    if [ "${#matches[@]}" -gt 1 ]; then
        echo "ERROR: ${#matches[@]} folders matched sample ${incsample} / slide ${incslide}:"
        printf '  %s\n' "${matches[@]}"
        exit 1
    fi

    srcdir="${matches[0]}"
    srcname="$(basename "${srcdir%/}")"
    # Rewrite both the slide and sample fields, wrong → correct, in the folder name.
    finalname="${srcname//${incslide}/${corslide}}"
    finalname="${finalname//${incsample}/${corsample}}"
    finalpath="${OUTPUT_BASE}/${finalname}"
    bundlepath="${BUNDLE_BASE}/${incsample}_${incslide}"
    destcorr="${BUCKET}/${finalname}"
    destwrong="${BUCKET}/${WRONG_ID_PREFIX}/${srcname}"

    if [ -e "${finalpath}" ]; then
        echo "ERROR: local destination already exists: ${finalpath}"
        exit 1
    fi
    # Refuse pre-existing bucket destinations now, so a clash can't surface mid-batch.
    if gcloud storage ls "${destcorr}/" >/dev/null 2>&1; then
        echo "ERROR: corrected destination already exists in bucket: ${destcorr}/"
        exit 1
    fi
    if gcloud storage ls "${destwrong}/" >/dev/null 2>&1; then
        echo "ERROR: wrong-id destination already exists in bucket: ${destwrong}/"
        exit 1
    fi

    R_INCSAMPLE+=("${incsample}"); R_INCSLIDE+=("${incslide}")
    R_CORSAMPLE+=("${corsample}"); R_CORSLIDE+=("${corslide}")
    R_SRCDIR+=("${srcdir}");       R_SRCNAME+=("${srcname}")
    R_FINALNAME+=("${finalname}"); R_FINALPATH+=("${finalpath}")
    R_BUNDLEPATH+=("${bundlepath}")
    R_DESTCORR+=("${destcorr}");   R_DESTWRONG+=("${destwrong}")
done

N="${#R_INCSAMPLE[@]}"
if [ "${N}" -eq 0 ]; then
    echo "ERROR: no valid samples to process."
    exit 1
fi

# ── Phase 2: show the plan, confirm once ────────────────────────────────────

echo
echo "Plan for ${N} sample(s):"
for ((i = 0; i < N; i++)); do
    echo
    echo "  [$((i + 1))/${N}] sample ${R_INCSAMPLE[$i]} → ${R_CORSAMPLE[$i]}, slide ${R_INCSLIDE[$i]} → ${R_CORSLIDE[$i]}"
    echo "        source   ${R_SRCDIR[$i]}"
    echo "        upload   ${R_FINALPATH[$i]}/  ->  ${R_DESTCORR[$i]}/"
    echo "        move     ${R_SRCDIR[$i]%/}/   ->  ${R_DESTWRONG[$i]}/"
done
echo

read -r -p "Proceed with all ${N} sample(s)? This mutates the shared bucket. [y/N] " REPLY
case "${REPLY}" in
    [yY]|[yY][eE][sS]) ;;
    *) echo "Aborted. Nothing was changed."; exit 0 ;;
esac

# ── Phase 3: process each sample ────────────────────────────────────────────
# A failed step sets REASON and returns 1; the bundle is left in place for retry.

process_one() {
    local i="$1"
    local incsample="${R_INCSAMPLE[$i]}"  corsample="${R_CORSAMPLE[$i]}"
    local srcdir="${R_SRCDIR[$i]}"
    local finalpath="${R_FINALPATH[$i]}"  bundlepath="${R_BUNDLEPATH[$i]}"
    local destcorr="${R_DESTCORR[$i]}"    destwrong="${R_DESTWRONG[$i]}"

    local run_id="output_corrected_${corsample}"
    local run_path="${OUTPUT_BASE}/${run_id}"

    REASON="download"
    mkdir -p "${bundlepath}"
    echo "Syncing full bundle from ${srcdir}"
    gcloud storage rsync -r "${srcdir}" "${bundlepath}/" || return 1

    # Clear any stale run folder; xeniumranger refuses to reuse an existing --id.
    REASON="rename"
    echo "Renaming → ${run_id} (region ${corsample})"
    rm -rf "${run_path}"
    (
        cd "${OUTPUT_BASE}" || exit 1
        "${XENIUMRANGER_BIN}" rename \
            --id="${run_id}" \
            --xenium-bundle="${bundlepath}" \
            --region-name="${corsample}"
    ) || return 1

    # Promote outs out of the run folder, then drop the rest.
    REASON="promote outs"
    if [ -e "${finalpath}" ]; then
        echo "✗ destination already exists: ${finalpath}"
        return 1
    fi
    echo "Promoting outs → ${finalpath}"
    mv "${run_path}/outs" "${finalpath}" || return 1
    rm -rf "${run_path}"

    # Upload before touching the original, so good data lands first.
    REASON="upload"
    echo "Uploading corrected bundle → ${destcorr}/"
    gcloud storage rsync -r "${finalpath}" "${destcorr}/" || return 1

    REASON="move wrong-id"
    echo "Moving incorrect folder → ${destwrong}/"
    gcloud storage mv --no-clobber "${srcdir%/}" "${destwrong}" || return 1

    echo "Removing input bundle: ${bundlepath}"
    rm -rf "${bundlepath}"

    REASON=""
    return 0
}

SUCCEEDED=()
FAILED=()

for ((i = 0; i < N; i++)); do
    echo
    echo "════════════════════════════════════════════════════════════════════"
    echo "[$((i + 1))/${N}] ${R_INCSAMPLE[$i]} → ${R_CORSAMPLE[$i]}"
    echo "════════════════════════════════════════════════════════════════════"
    REASON=""
    if process_one "${i}"; then
        SUCCEEDED+=("${R_INCSAMPLE[$i]} → ${R_CORSAMPLE[$i]}")
        echo "✓ ${R_CORSAMPLE[$i]} done."
    else
        FAILED+=("${R_INCSAMPLE[$i]} → ${R_CORSAMPLE[$i]} (failed at: ${REASON:-unknown}; bundle kept at ${R_BUNDLEPATH[$i]})")
        echo "✗ ${R_INCSAMPLE[$i]} failed at: ${REASON:-unknown} — skipping."
    fi
done

# ── Phase 4: summary ────────────────────────────────────────────────────────

echo
echo "════════════════════════════════════════════════════════════════════"
echo "Summary: ${#SUCCEEDED[@]} succeeded, ${#FAILED[@]} failed (of ${N})."
echo "════════════════════════════════════════════════════════════════════"
if [ "${#SUCCEEDED[@]}" -gt 0 ]; then
    echo "Succeeded:"
    printf '  ✓ %s\n' "${SUCCEEDED[@]}"
fi
if [ "${#FAILED[@]}" -gt 0 ]; then
    echo "Failed:"
    printf '  ✗ %s\n' "${FAILED[@]}"
    exit 1
fi
