import pandas as pd
import numpy as np

FILE_A = "metric_summary_20260101_20260401.csv"
FILE_B = "TotalQC_PreTisType_Updated-22Dec2025sas - Jan-Mar2026 adds.csv"
KEY_COLS = ["run_name", "region_name"]

df_a = pd.read_csv(FILE_A, dtype=str)
df_b = pd.read_csv(FILE_B, dtype=str)

# Normalize whitespace
df_a.columns = df_a.columns.str.strip()
df_b.columns = df_b.columns.str.strip()
for df in [df_a, df_b]:
    for col in df.select_dtypes("object").columns:
        df[col] = df[col].str.strip()

shared_cols = [c for c in df_a.columns if c in df_b.columns]
missing_in_b = [c for c in df_a.columns if c not in df_b.columns]
missing_in_a = [c for c in df_b.columns if c not in df_a.columns]

print(f"Rows in metric_summary: {len(df_a)}")
print(f"Rows in TotalQC:        {len(df_b)}")
print(f"Shared columns: {len(shared_cols)}")
print(f"Columns only in metric_summary ({len(missing_in_b)}): {missing_in_b}")
print(f"Columns only in TotalQC ({len(missing_in_a)}): {missing_in_a}")
print()

# Check for duplicate keys within each file
dup_a = df_a[df_a.duplicated(KEY_COLS, keep=False)]
dup_b = df_b[df_b.duplicated(KEY_COLS, keep=False)]
if not dup_a.empty:
    print(f"WARNING: {len(dup_a)} duplicate keys in metric_summary:")
    print(dup_a[KEY_COLS].to_string())
if not dup_b.empty:
    print(f"WARNING: {len(dup_b)} duplicate keys in TotalQC:")
    print(dup_b[KEY_COLS].to_string())
print()

def compare_values(a, b):
    """
    Returns:
      'equal'       - identical or within floating-point noise (< 0.001% rel diff)
      'rounding'    - numeric, differ only by rounding/truncation (< 1% rel diff)
      'different'   - substantively different values
    """
    if pd.isna(a) and pd.isna(b):
        return "equal"
    if pd.isna(a) or pd.isna(b):
        return "different"
    try:
        fa, fb = float(a), float(b)
        if np.isnan(fa) and np.isnan(fb):
            return "equal"
        if np.isnan(fa) or np.isnan(fb):
            return "different"
        if fa == fb:
            return "equal"
        rel = abs(fa - fb) / max(abs(fa), abs(fb), 1e-15)
        if rel < 1e-5:
            return "equal"
        if rel < 0.01:    # within 1% — treat as rounding artifact
            return "rounding"
        return "different"
    except (ValueError, TypeError):
        return "equal" if str(a).lower() == str(b).lower() else "different"

# Merge on key columns — outer join to catch rows only in one file
df_merged = df_a[shared_cols].merge(
    df_b[shared_cols],
    on=KEY_COLS,
    how="outer",
    suffixes=("_metric", "_totalqc"),
    indicator=True,
)

comparison_cols = [c for c in shared_cols if c not in KEY_COLS]

diff_rows = []

for _, row in df_merged.iterrows():
    run, region, source = row["run_name"], row["region_name"], row["_merge"]

    if source == "left_only":
        diff_rows.append({
            "run_name": run, "region_name": region,
            "difference_type": "row_only_in_metric_summary",
            "difference_detail": "Row exists in metric_summary but not in TotalQC",
        })
    elif source == "right_only":
        diff_rows.append({
            "run_name": run, "region_name": region,
            "difference_type": "row_only_in_TotalQC",
            "difference_detail": "Row exists in TotalQC but not in metric_summary",
        })
    else:
        real_diffs = []
        rounding_diffs = []
        for col in comparison_cols:
            val_a = row.get(f"{col}_metric", np.nan)
            val_b = row.get(f"{col}_totalqc", np.nan)
            result = compare_values(val_a, val_b)
            if result == "different":
                real_diffs.append(f"{col}: [metric={val_a}] vs [totalqc={val_b}]")
            elif result == "rounding":
                rounding_diffs.append(f"{col}: [metric={val_a}] vs [totalqc={val_b}]")

        if real_diffs:
            diff_rows.append({
                "run_name": run, "region_name": region,
                "difference_type": "value_mismatch",
                "difference_detail": " | ".join(real_diffs),
            })
        elif rounding_diffs:
            diff_rows.append({
                "run_name": run, "region_name": region,
                "difference_type": "rounding_only",
                "difference_detail": " | ".join(rounding_diffs),
            })

n_value_diff  = sum(1 for r in diff_rows if r["difference_type"] == "value_mismatch")
n_rounding    = sum(1 for r in diff_rows if r["difference_type"] == "rounding_only")
n_only_metric = sum(1 for r in diff_rows if r["difference_type"] == "row_only_in_metric_summary")
n_only_total  = sum(1 for r in diff_rows if r["difference_type"] == "row_only_in_TotalQC")

print(f"Rows only in metric_summary:           {n_only_metric}")
print(f"Rows only in TotalQC:                  {n_only_total}")
print(f"Rows with substantive value mismatch:  {n_value_diff}")
print(f"Rows with rounding-only differences:   {n_rounding}")
print(f"Total rows in differences output:      {len(diff_rows)}")

if diff_rows:
    df_diff = pd.DataFrame(diff_rows, columns=["run_name", "region_name", "difference_type", "difference_detail"])
    out_path = "differences_metric_vs_totalqc.csv"
    df_diff.to_csv(out_path, index=False)
    print(f"\nSaved: {out_path}")

    # Pretty-print substantive mismatches
    vm = [r for r in diff_rows if r["difference_type"] == "value_mismatch"]
    if vm:
        print(f"\nSubstantive value mismatches ({len(vm)} rows):")
        for r in vm:
            print(f"  {r['run_name']} / {r['region_name']}")
            for part in r["difference_detail"].split(" | "):
                print(f"    {part}")
    else:
        print("\nNo substantive value mismatches — all numeric differences are rounding only.")
else:
    print("\nNo differences found — files are effectively identical.")
