# Xenium QC and Data Management

This repo contains scripts, notebooks, and data for QC reporting and sample ID correction on 10x Genomics Xenium spatial transcriptomics runs.

## Directory Structure

```
xenium/
├── scripts/
│   ├── rename/          # 3-step pipeline to correct a sample ID swap
│   └── metrics/         # Scripts to import metrics_summary.csv files from GCS
├── data/
│   ├── bundles/         # Raw Xenium bundles (input to the rename pipeline)
│   ├── renamed/         # xeniumranger rename output (corrected bundles)
│   └── 2026_metric_summaries/   # Collected metrics CSVs for 2026 runs
├── analysis/
│   └── metric_vs_totalqc_comparison/   # Validate aggregated metrics against TotalQC tracker
├── qc/                  # Per-experiment QC notebooks and outputs
└── xenium_qc_report.ipynb       # QC report template notebook
```

---

## Scripts

### `scripts/rename/` — Sample ID Swap Correction Pipeline

Three scripts that must be run in order to fix a slide swap in **EXP-02059 / EXP-02060**, where samples were loaded on the wrong slides.

| Script | Purpose |
|---|---|
| `01_import_bundles.sh` | Downloads required bundle files (experiment.xenium, metrics_summary.csv, analysis_summary.html) from GCS into `data/bundles/` |
| `02_rename.sh` | Runs `xeniumranger rename` on each bundle to swap TSS IDs and cassette names, writing corrected output to `data/renamed/` |
| `03_collect_csvs.sh` | Copies the corrected metrics_summary.csv from each renamed bundle into `qc/EXP-02059-02060/csvs/`, named by TSS ID |

### `scripts/metrics/` — Metrics Import

| Script | Purpose |
|---|---|
| `import_2026_bulk.sh` | Scans a GCS bucket for all folders containing `_2026` and downloads their metrics_summary.csv into `data/2026_metric_summaries/` |
| `import_targeted.sh` | Downloads metrics_summary.csv for a specific comma-separated list of sample IDs into `data/2026_metric_summaries/` |

---

## Data

See the README in each subfolder for details.

- **`data/bundles/`** — raw input bundles for the EXP-02059-02060 rename pipeline
- **`data/renamed/`** — xeniumranger rename output with corrected sample metadata
- **`data/2026_metric_summaries/`** — flat collection of metrics CSVs for all 2026 runs

---

## Analysis

### `analysis/`

Each subfolder is an isolated, self-contained analysis — its own scripts, inputs, and outputs together. Add a new subfolder for each independent investigation rather than placing files directly in `analysis/`.

| Subfolder | Description |
|---|---|
| `metric_vs_totalqc_comparison/` | Compares the aggregated Jan–Apr 2026 metrics CSV against the manually maintained TotalQC tracking spreadsheet; outputs a differences report |

---

## QC

### `qc/`

One subfolder per experiment (e.g., `qc/EXP-02024-02031/`), each containing:
- `xenium_qc_report.ipynb` — executed QC notebook for that experiment
- `xenium_qc_report.csv` — aggregated metrics table
- `<EXP>_figs.pdf` — exported QC plots
- `csvs/` — per-sample metrics_summary.csv files used as input (gitignored)

### `xenium_qc_report.ipynb`

The template notebook used to generate QC reports. Accepts metrics_summary.csv files either by HISE UUID list or by pointing to a local folder. Produces bar charts and scatter plots for key metrics (cell count, transcripts per cell, decode rates, false positive rate, segmentation fractions) and exports a PDF report. Copy into the relevant `qc/EXP-XXXXX/` folder before running.
