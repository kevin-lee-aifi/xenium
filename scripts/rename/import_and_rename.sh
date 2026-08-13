#!/bin/bash
# For each sample below: download its xenium bundle, rewrite the wrong sample/slide
# IDs with `xeniumranger rename`, upload the corrected bundle, and move the original
# aside under wrong_id/ in the bucket. A failed sample is skipped and reported.

set -uo pipefail

# "WRONG_SAMPLE, WRONG_SLIDE, CORRECT_SAMPLE, CORRECT_SLIDE" — one line per sample.
SAMPLES=(
    "TSS10546-041, 0082205, TSS10546-042, 0082215"
)

BUCKET="gs://temp-xenium-hise-transfer"
BUNDLE_BASE="/home/workspace/xenium/data/bundles"
OUTPUT_BASE="/home/workspace/xenium/data/renamed"
XENIUMRANGER="/home/workspace/xeniumranger-xenium4.0/xeniumranger"

mkdir -p "$BUNDLE_BASE" "$OUTPUT_BASE"
bucket=$(gcloud storage ls "$BUCKET/")

# Resolve each row to its source folder (matched by both wrong IDs) and show the plan.
rows=()
echo "Plan:"
for row in "${SAMPLES[@]}"; do
    IFS=', ' read -r ws wl cs cl <<< "$row"
    match=$(awk -v s="__${ws}__" -v l="__${wl}__" 'index($0,s) && index($0,l)' <<< "$bucket")
    n=$(grep -c . <<< "$match")
    if [[ "$n" -ne 1 ]]; then
        echo "ERROR: expected exactly 1 bucket folder for $ws / $wl, found $n"; exit 1
    fi
    srcname=$(basename "${match%/}")
    rows+=("$ws|$wl|$cs|$cl|$srcname")
    echo "  $ws/$wl → $cs/$cl   ($srcname)"
done

read -r -p "Proceed? This mutates $BUCKET. [y/N] " ans
[[ "$ans" =~ ^[Yy] ]] || { echo "Aborted."; exit 0; }

ok=(); fail=()
for r in "${rows[@]}"; do
    IFS='|' read -r ws wl cs cl srcname <<< "$r"
    src="$BUCKET/$srcname"
    finalname="${srcname//$wl/$cl}"; finalname="${finalname//$ws/$cs}"
    bundle="$BUNDLE_BASE/${ws}_${wl}"
    run="$OUTPUT_BASE/output_corrected_${cs}"
    final="$OUTPUT_BASE/$finalname"

    echo; echo "=== $ws → $cs ==="
    if mkdir -p "$bundle" &&
       gcloud storage rsync -r "$src" "$bundle/" &&
       rm -rf "$run" &&
       ( cd "$OUTPUT_BASE" && "$XENIUMRANGER" rename \
             --id="output_corrected_${cs}" --xenium-bundle="$bundle" --region-name="$cs" ) &&
       rm -rf "$final" && mv "$run/outs" "$final" && rm -rf "$run" &&
       gcloud storage rsync -r "$final" "$BUCKET/$finalname/" &&
       gcloud storage mv --no-clobber "$src" "$BUCKET/wrong_id/$srcname" &&
       rm -rf "$bundle"; then
        ok+=("$cs"); echo "✓ $cs"
    else
        fail+=("$ws → $cs"); echo "✗ $ws failed (bundle kept: $bundle)"
    fi
done

echo; echo "Done: ${#ok[@]} succeeded, ${#fail[@]} failed."
if ((${#fail[@]})); then printf '  ✗ %s\n' "${fail[@]}"; exit 1; fi
