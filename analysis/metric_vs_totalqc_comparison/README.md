# analysis/metric_vs_totalqc_comparison/

Validates the aggregated 2026 metrics export against the manually maintained TotalQC tracking spreadsheet to surface any discrepancies.

## Files

| File | Role |
|---|---|
| `metric_summary_20260101_20260401.csv` | Input — aggregated metrics_summary data for all runs Jan–Apr 2026 |
| `TotalQC_PreTisType_Updated-22Dec2025sas - Jan-Mar2026 adds.csv` | Input — manually maintained master QC tracking spreadsheet |
| `compare_csvs.py` | Script — joins the two files on `run_name` + `region_name` and reports row-level and value-level differences |
| `differences_metric_vs_totalqc.csv` | Output — rows where the two files differ (missing rows, value mismatches, or rounding-only differences) |

## Running

Run from this directory so the relative file paths in the script resolve correctly:

```bash
cd analysis/metric_vs_totalqc_comparison
python compare_csvs.py
```

## Result

At last run, no substantive value mismatches were found — all differences were rounding only (scientific notation vs. truncated decimals in the TotalQC sheet).
