#!/usr/bin/env python
"""Xenium QC Report Module.

Single entry point for a Xenium QC run. Fill in the metadata in the CONFIG
section, run the script, and it will:

  1. create the per-experiment folder ``qc/<EXP_ID>/`` (with ``csvs/`` and
     ``htmls/`` subdirs),
  2. download the per-sample ``metrics_summary.csv`` / ``analysis_summary.html``
     files into it,
  3. aggregate the CSVs into ``qc/<EXP_ID>/xenium_qc_report.csv``, and
  4. render ``qc/<EXP_ID>/Xenium_qc_report_<EXP_ID>.pdf``.

Keep this as the one canonical script in the ``xenium/`` folder — edit only the
CONFIG values below per run; do not copy it into the per-experiment folders.

There are two ways to get the per-sample files into this script:

- ``download_metrics_from_bucket()`` — pull ``metrics_summary.csv`` (and
  ``analysis_summary.html``) files for a list of slides directly from the
  Xenium GCS bucket.
- ``aggregate_from_local()`` — aggregate ``metrics_summary.csv`` files already
  on disk.

Before running, edit the CONFIG section below.

    Required:
      EXP_ID    — experiment ID; also used to build the QC output paths.
      RUN_NAME  — run name, used in the report title.

    Download (GCS) settings:
      BUCKET_NAME — GCS bucket holding the metrics files (no ``gs://`` prefix).
      SLIDE_IDS   — comma-separated list of slide IDs to fetch.

The remaining values are derived from ``EXP_ID`` / ``RUN_NAME`` and do not need
to be edited.

Usage:
    python xenium_qc_report.py
"""

from pathlib import Path

import pandas as pd
import matplotlib.pyplot as plt
from matplotlib.backends.backend_pdf import PdfPages

# ──────────────────────────────────────────────────────────────────────────────
# CONFIG — edit these
# ──────────────────────────────────────────────────────────────────────────────

# ── Required ──────────────────────────────────────────────────────────────────
EXP_ID = "EXP-02152-02153"
RUN_NAME = "061226"  # e.g. "060526"

# ── Download cell (GCS) ───────────────────────────────────────────────────────
BUCKET_NAME = "temp-xenium-hise-transfer"
SLIDE_IDS = "0097818, 0097875"  # comma-separated slide IDs

# ── Derived (no need to edit) ─────────────────────────────────────────────────
BASE_DIR = Path("/home/workspace/xenium/qc") / EXP_ID
all_qc_report_path = BASE_DIR / "csvs"
html_output = BASE_DIR / "htmls"
output_dir = BASE_DIR
title_description = f"Xenium QC report for run name {EXP_ID}_{RUN_NAME}"
pdf_file_name = f"Xenium_qc_report_{EXP_ID}.pdf"

SUFFIX = "_metric_summary.csv"

# Plot palettes
COLORS = ['#9e0142', '#d53e4f', '#f46d43', '#fdae61', '#fee08b',
          '#e6f598', '#abdda4', '#66c2a5', '#3288bd', '#5e4fa2']
COL = ['#d53e4f', '#66c2a5', '#5e4fa2']


# ──────────────────────────────────────────────────────────────────────────────
# Download cell: pull metrics_summary.csv files from the GCS bucket
# ──────────────────────────────────────────────────────────────────────────────

def download_metrics_from_bucket():
    """Download per-slide metrics_summary.csv and analysis_summary.html from GCS."""
    from google.cloud import storage

    slide_list = [s.strip() for s in SLIDE_IDS.split(",")]
    all_qc_report_path.mkdir(parents=True, exist_ok=True)
    html_output.mkdir(parents=True, exist_ok=True)

    client = storage.Client()
    bucket = client.bucket(BUCKET_NAME)
    names = [blob.name for blob in bucket.list_blobs()]

    for slide_id in slide_list:
        print(f"Looking for slide {slide_id}...")

        matches = [
            name for name in names
            if slide_id in name and name.endswith("metrics_summary.csv")
        ]

        if not matches:
            print(f"  ERROR: No match found for {slide_id}")
            continue

        print(f"  Found {len(matches)} sample(s) for slide {slide_id}")

        for match in matches:
            # Extract the run folder, e.g.
            # output-XETG00195__0082215__TSS10546-041__20260605__173502
            folder = match.split("/")[0]
            parts = folder.split("__")

            # parts: [output-XETG00195, 0082215, TSS10546-041, 20260605, 173502]
            tss_id = parts[2] if len(parts) > 2 else "UNKNOWN"
            prefix = f"{slide_id}__{tss_id}"

            # Download metrics_summary.csv
            csv_dst = all_qc_report_path / f"{prefix}_metric_summary.csv"
            bucket.blob(match).download_to_filename(str(csv_dst))
            print(f"  Done -> {csv_dst}")

            # Download analysis_summary.html from the same run folder
            html_blob = f"{folder}/analysis_summary.html"
            if html_blob in names:
                html_dst = html_output / f"{prefix}_analysis_summary.html"
                bucket.blob(html_blob).download_to_filename(str(html_dst))
                print(f"  Done -> {html_dst}")
            else:
                print(f"  WARNING: No analysis_summary.html found in {folder}")


# ──────────────────────────────────────────────────────────────────────────────
# Aggregate metrics summary files already on disk
# ──────────────────────────────────────────────────────────────────────────────

def discover_samples():
    """Derive the sample ID list from the metrics CSVs in the csvs folder.

    Filenames look like ``{slide_id}__{tss_id}_metric_summary.csv``; the sample
    ID is the full ``{slide_id}__{tss_id}`` prefix (the TSS id alone can repeat
    across slides, so it isn't unique on its own).
    """
    sample_list = sorted(
        p.name[: -len(SUFFIX)]
        for p in Path(all_qc_report_path).glob(f"*{SUFFIX}")
    )
    print(f"Found {len(sample_list)} sample(s):")
    for s in sample_list:
        print(f"  {s}")
    return sample_list


def aggregate_from_local(sample_list):
    """Aggregate exactly one metrics file per expected sample into one CSV.

    Aggregates one file per expected sample rather than globbing every CSV in
    the directory, so stale files from previous runs (or other experiments)
    can't be folded into the report.
    """
    csv_paths = []
    for sample_id in sample_list:
        matches = sorted(Path(all_qc_report_path).glob(f"*{sample_id}*.csv"))
        if not matches:
            raise FileNotFoundError(
                f"No metrics summary CSV found for sample {sample_id} in {all_qc_report_path}"
            )
        if len(matches) > 1:
            print(f"WARNING: multiple files for {sample_id}, using first: {matches[0].name}")
        csv_paths.append(matches[0])

    print(f"Aggregating {len(csv_paths)} files:")
    for p in csv_paths:
        print(f"  {p.name}")

    df_aggregated_qc_report = pd.concat(
        [pd.read_csv(p) for p in csv_paths],
        ignore_index=True,
    )

    output_qc_file_name = 'xenium_qc_report.csv'
    df_aggregated_qc_report.to_csv(Path(output_dir) / output_qc_file_name, index=False)
    return df_aggregated_qc_report


# ──────────────────────────────────────────────────────────────────────────────
# Visualizations
# ──────────────────────────────────────────────────────────────────────────────

def prepare_plot_df(df_aggregated_qc_report):
    """Drop all-NaN columns, then sanity-check the aggregated table before plotting."""
    plot_df = df_aggregated_qc_report.dropna(axis=1, how='all')

    print(f"Aggregated {plot_df.shape[0]} samples x {plot_df.shape[1]} metrics")
    print(f"Run name(s): {sorted(plot_df['run_name'].unique())}")
    print(f"Columns: {list(plot_df.columns)}")
    return plot_df


def bar_plot(pdf_pages, plot_df, y_col, ylabel, title, color, df=None):
    df = plot_df if df is None else df
    fig, ax = plt.subplots(figsize=(8, 5))
    ax.bar(df['region_name'], df[y_col], color=color)
    plt.setp(ax.get_xticklabels(), rotation=60, ha='right')
    ax.set_xlabel('Tissue ID')
    ax.set_ylabel(ylabel)
    ax.set_title(title)
    fig.tight_layout()
    pdf_pages.savefig(fig)
    plt.close(fig)


def stacked_bar(pdf_pages, plot_df, value_cols, title, ylabel='Value', df=None, palette=None):
    df = plot_df if df is None else df
    palette = COL if palette is None else palette
    fig, ax = plt.subplots(figsize=(9, 7))
    bottoms = pd.Series(0.0, index=df.index)
    for i, c in enumerate(value_cols):
        ax.bar(df['region_name'], df[c], bottom=bottoms, label=c, color=palette[i])
        bottoms = bottoms + df[c]
    ax.set_xlabel('Region Name')
    ax.set_ylabel(ylabel)
    ax.set_title(title)
    ax.legend(title='Metrics', bbox_to_anchor=(1.05, 1), loc='upper left')
    ax.grid(True, linestyle='--', color='gray', alpha=0.6)
    plt.setp(ax.get_xticklabels(), rotation=45, ha='right')
    fig.tight_layout()
    pdf_pages.savefig(fig)
    plt.close(fig)


def render_pdf(plot_df):
    """Render all QC visualizations into the multi-page PDF."""
    pdf_path = Path(output_dir) / pdf_file_name
    pdf_pages = PdfPages(pdf_path)

    # Number of cells detected
    bar_plot(pdf_pages, plot_df, 'num_cells_detected', 'Number of cells',
             'Number of cells detected by region', COLORS[6])

    # Transcripts and genes per tissue
    plt.figure(figsize=(8, 5))
    plt.bar(plot_df['region_name'], plot_df['median_transcripts_per_cell'], color=COLORS[7])
    plt.plot(plot_df['region_name'], plot_df['median_genes_per_cell'], color=COLORS[1],
             marker='o', label='Median Genes per Cell')
    plt.xticks(rotation=60, ha='right')
    plt.xlabel('Tissue ID')
    plt.ylabel('Median Transcripts per Cell')
    plt.title('Median Transcripts per Cell by Region')
    plt.legend()
    plt.tight_layout()
    pdf_pages.savefig()
    plt.close()

    # Estimated false positive transcripts
    bar_plot(
        pdf_pages, plot_df,
        'estimated_number_of_false_positive_transcripts_per_cell',
        'Number of False Positive Transcripts per Cell',
        'Estimated False Positive Transcripts per Region',
        COLORS[1],
    )

    # Decoded transcripts
    plt.figure(figsize=(8, 5))
    plt.scatter(plot_df['region_name'], plot_df['fraction_transcripts_decoded_q20'],
                color=COLORS[8], label='Fraction Transcripts Decoded Q20', marker='^', s=120)
    plt.scatter(plot_df['region_name'], plot_df['fraction_transcripts_assigned'],
                color=COLORS[2], label='Fraction Transcripts Assigned', marker='o', s=100)
    plt.scatter(plot_df['region_name'], plot_df['fraction_empty_cells'],
                color=COLORS[7], label='Fraction Empty cells', marker='x', s=100)
    plt.xticks(rotation=60, ha='right')
    plt.xlabel('Region Name')
    plt.ylabel('Fraction')
    plt.title('Decoded Transcript Fractions')
    plt.ylim(0, 1)
    plt.legend(loc='upper left', bbox_to_anchor=(1, 1))
    plt.grid(True, linestyle='--', color='gray', alpha=0.6)
    plt.tight_layout()
    pdf_pages.savefig()
    plt.close()

    # Cells per 100um sq
    bar_plot(pdf_pages, plot_df, 'cells_per_100um2', 'N Cells', 'Cells per 100 um sq', COLORS[4])

    # Segmentation fractions and counts
    stacked_bar(
        pdf_pages, plot_df,
        [
            'segmented_cell_boundary_frac',
            'segmented_cell_interior_frac',
            'segmented_cell_nuc_expansion_frac',
        ],
        title='Segmentation Fractions by Tissue',
    )
    stacked_bar(
        pdf_pages, plot_df,
        [
            'segmented_cell_boundary_count',
            'segmented_cell_interior_count',
            'segmented_cell_nuc_expansion_count',
        ],
        title='Segmentation Counts by Tissue',
    )

    # Median transcripts per panel
    plt.figure(figsize=(8, 5))
    panels = plot_df['panel_name'].unique()
    plt.boxplot(
        [plot_df.loc[plot_df['panel_name'] == p, 'median_transcripts_per_cell'] for p in panels],
        tick_labels=panels,
        showfliers=False,
    )
    for i, panel in enumerate(panels, start=1):
        panel_data = plot_df.loc[plot_df['panel_name'] == panel, 'median_transcripts_per_cell']
        plt.scatter(
            [i] * len(panel_data),
            panel_data,
            color=COLORS[9],
            alpha=0.8,
            s=50,
            label='Points' if i == 1 else "_",
        )
    plt.xlabel('Panel Name')
    plt.ylabel('Median Transcripts per Cell')
    plt.title('Median Transcripts per Cell by Panel')
    plt.tight_layout()
    pdf_pages.savefig()
    plt.close()

    pdf_pages.close()
    print(f"Wrote {pdf_path}")


# ──────────────────────────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────────────────────────

def main():
    # 0. Create the per-experiment QC folder (qc/<EXP_ID>/ and its csvs/htmls
    #    subdirs). Everything below — downloaded CSVs/HTMLs, the aggregated CSV,
    #    and the PDF — is written inside this folder.
    output_dir.mkdir(parents=True, exist_ok=True)
    all_qc_report_path.mkdir(parents=True, exist_ok=True)
    html_output.mkdir(parents=True, exist_ok=True)
    print(f"Output folder: {output_dir}")

    # 1. Download the per-sample metrics files from the GCS bucket.
    #    (Comment out if the CSVs are already in the csvs folder.)
    download_metrics_from_bucket()

    # 2. Aggregate the per-sample CSVs on disk.
    sample_list = discover_samples()
    df_aggregated_qc_report = aggregate_from_local(sample_list)

    # 3. Render the QC PDF.
    plot_df = prepare_plot_df(df_aggregated_qc_report)
    render_pdf(plot_df)


if __name__ == "__main__":
    main()
