"""Aggregate all metrics_summary CSVs into one file with a run_date column."""

import re
from pathlib import Path

import pandas as pd

INPUT_DIR = Path("/home/workspace/xenium/data/2026_metric_summaries")
OUTPUT = Path("/home/workspace/xenium/data/metrics_summary_2026_all.csv")

frames = []
for f in sorted(INPUT_DIR.glob("*_metric_summary.csv")):
    if f.stat().st_size == 0:
        print(f"WARNING: skipping empty file {f.name}")
        continue
    parts = f.stem.replace("_metric_summary", "").split("__")
    try:
        date = pd.to_datetime(parts[3], format="%Y%m%d")
    except (IndexError, ValueError):
        date = pd.NaT
    df = pd.read_csv(f)
    df.insert(0, "run_date", date)
    frames.append(df)
combined = pd.concat(frames, ignore_index=True)
combined.to_csv(OUTPUT, index=False)
print(f"Wrote {len(combined)} rows to {OUTPUT}")
