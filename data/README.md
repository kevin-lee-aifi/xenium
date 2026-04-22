# data/

This folder contains all local data used by the Xenium QC pipeline. Contents are generally gitignored and re-importable from GCS.

---

## data/2026_metric_summaries/

A flat collection of `metrics_summary.csv` files for all 2026 Xenium runs, imported from GCS. Used as input to `xenium_qc_report.ipynb` for QC reporting.

### File Naming Convention

```
output-<instrument>__<cassette>__<sample>__<date>__<time>_metric_summary.csv
```

| Field | Example | Description |
|---|---|---|
| `instrument` | `XETG00123` | Xenium instrument serial number |
| `cassette` | `0077194` | Cassette (slide) ID |
| `sample` | `TSS10546-001` | Tissue section sample ID |
| `date` | `20260213` | Run date (YYYYMMDD) |
| `time` | `231726` | Run start time (HHMMSS) |

Multiple files can share the same cassette and date if multiple samples were run on the same slide simultaneously.

### How this folder was populated

- **Bulk import**: `scripts/metrics/import_2026_bulk.sh` scans the `gs://temp-xenium-hise-transfer` bucket for all folders containing `_2026` and downloads their metrics_summary.csv.
- **Targeted import**: `scripts/metrics/import_targeted.sh` downloads metrics for a specific list of sample IDs defined in the `SAMPLES` variable.

---

## data/bundles/

Raw Xenium bundles for the **EXP-02059 / EXP-02060 sample ID swap correction**. These are the input to `scripts/rename/02_rename.sh`.

### Contents

Six sample folders, one per tissue section involved in the swap:

| Folder | Slide | Position |
|---|---|---|
| `TSS05029-004` | Slide 1 (EXP-02059) | A1 |
| `TSS05029-005` | Slide 2 (EXP-02060) | A1 |
| `TSS06403-004` | Slide 1 (EXP-02059) | A2 |
| `TSS06403-005` | Slide 2 (EXP-02060) | A2 |
| `TSS08944-007` | Slide 1 (EXP-02059) | A3 |
| `TSS08944-008` | Slide 2 (EXP-02060) | A3 |

Each folder contains the three files required by `xeniumranger rename`:

- `experiment.xenium` — run metadata including cassette and region names
- `metrics_summary.csv` — per-sample QC metrics from the original run
- `analysis_summary.html` — HTML summary report from the original run

### How this folder was populated

Run `scripts/rename/01_import_bundles.sh`. It pulls these three files for each sample from the `gs://temp-xenium-hise-transfer` GCS bucket. Update the `SAMPLES` variable in the script to change which samples are fetched.

---

## data/renamed/

Output of `xeniumranger rename` for the **EXP-02059 / EXP-02060 sample ID swap correction**. Each subfolder is the corrected bundle for one sample, with the TSS ID and cassette name updated to reflect the swap.

### Naming Convention

Folders follow the pattern `output_corrected_<NEW_TSS_ID>/`, where `NEW_TSS_ID` is the corrected (post-swap) sample ID assigned by `scripts/rename/02_rename.sh`.

### Structure of Each Subfolder

```
output_corrected_<TSS_ID>/
├── outs/
│   ├── experiment.xenium      # corrected run metadata
│   ├── metrics_summary.csv    # corrected metrics with updated IDs
│   └── analysis_summary.html  # corrected HTML report
├── XENIUM_RANGER_RENAMER_CS/  # xeniumranger internal pipeline logs
├── _log, _perf, _versions     # xeniumranger run metadata
└── output_corrected_<TSS_ID>.mri.tgz
```

The files in `outs/` are the deliverables. The rest is xeniumranger pipeline scaffolding and can be ignored for downstream use.

### How this folder was populated

Run `scripts/rename/02_rename.sh`. The corrected metrics_summary.csv files from `outs/` are then collected into `qc/EXP-02059-02060/csvs/` by `scripts/rename/03_collect_csvs.sh`.
