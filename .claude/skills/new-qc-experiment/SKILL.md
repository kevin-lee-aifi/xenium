---
name: new-qc-experiment
description: Scaffold a new per-experiment QC folder under qc/ from an experiment number. Use when the user wants to start a QC report for a new experiment, create/set up a new EXP folder in qc/, or "make a new experiment folder". Takes one or two EXP numbers, names the folder in the repo convention (EXP-NNNNN or EXP-NNNNN-NNNNN), creates a csvs/ subfolder, and copies in the template xenium_qc_report.ipynb.
---

# New QC Experiment Folder

Create a new per-experiment QC folder under `qc/`, matching the naming
convention of the existing folders.

## What it produces

For experiment number(s) like `2093` or `2080 2081`, it creates:

```
qc/EXP-02093/                 (or qc/EXP-02080-02081/ for a pair)
├── csvs/                     # input metrics_summary.csv files (gitignored)
└── xenium_qc_report.ipynb    # copy of the repo-root template notebook
```

## Naming convention

- Experiment numbers are zero-padded to **5 digits**.
- A single experiment → `EXP-NNNNN`.
- Two experiments → `EXP-NNNNN-NNNNN` (hyphen-separated).

(Some legacy folders use underscores or unpadded numbers; new folders should
use the hyphen + 5-digit form above.)

## How to run

Run the helper script with the experiment number(s). It accepts them in any
common form (`2093`, `EXP-02093`, `2080 2081`, `2080-2081`):

```bash
bash .claude/skills/new-qc-experiment/new_qc_experiment.sh <EXP> [EXP2]
```

The script finds the repo root automatically, refuses to overwrite an existing
folder, and prints what it created.

## Notes

- The `csvs/` folder is gitignored (`**/csvs/`), so it won't be committed —
  that's expected; it holds the per-sample `metrics_summary.csv` inputs.
- After scaffolding, the next steps (not done by this skill) are usually:
  populate `csvs/` with the metrics CSVs, then open and run the notebook to
  produce `xenium_qc_report.csv` and the exported PDF.
