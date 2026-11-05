# Torque Processing Platform

An R Shiny app that processes isometric and isokinetic knee torque files in a standardized, documented way: contraction detection, peak torque, rate of torque development (RTD), work, angle at peak, H:Q ratio, and limb symmetry, organized by participant through a key file.

- **Methods topic:** Building automated and semi-automated processing tools for standardized data handling
- **Course:** KINE 8630, Unit 3 project

## Purpose

This app is a worked example for the Unit 3 project, in which students build their own platform to bring two data sources together and process them the same way every time. It shows the pieces a standardized pipeline needs:

- a **key file** that links every data file to a participant, group, limb, trial, and body mass;
- **automatic file reading and task detection**, with clear rejection rules (for example, a minimum sampling rate);
- **default processing parameters tied to a published standard**, all editable and recorded;
- a **QC step** where a person reviews every contraction, can exclude it or move an onset, and every change is logged with a reason;
- **exports** that include every table, the parameters used, the QC log, and an auto-generated methods paragraph.

## Run

Download this folder, then open `app.R` in RStudio and click **Run App**, or in R:

```r
shiny::runApp("path/to/torque-processing-platform")
```

Any missing packages (shiny, bslib, DT, plotly, signal, dplyr, tidyr, readxl, openxlsx, zip) install the first time it runs. It runs locally, so no data leaves your machine.

## Using the example data

**Multi-participant set ([`example-data/`](example-data/)).** 48 simulated 1000 Hz files from 4 participants (2 ACLR, 2 Healthy), both limbs, 2 sessions, and 3 contraction types, with a matching `example_key.csv`. Load the key and all 48 files and everything is assigned automatically. See the [example-data README](example-data/README.md).

**Single-trial course files ([`../data/`](../data/)).** These also work, with two extra steps that are good practice:

1. Rename the three 1000 Hz files with a record number first, for example `1_isom.csv`, `1_isok60.csv`, and `1_isok240.csv`, or load them as-is and double-click the blank record column in the Files table to assign one.
2. Make a key file with one row for that record (see `key_template.csv` for the layout).

The 100 Hz versions are rejected because they fall below the app's 250 Hz minimum, which is a useful example of a rejection rule.

## Key file (.csv or .xlsx)

One row per **record**, meaning one limb tested in one trial. Columns are read **by position**, so the header names don't matter:

| 1 record | 2 participant ID | 3 group | 4 injured / nondom limb | 5 limb tested | 6 body mass (kg) | 7 trial |
|---|---|---|---|---|---|---|
| 1 | P001 | ACLR | L | L | 72.4 | 1 |
| 2 | P001 | ACLR | L | R | 72.4 | 1 |
| 3 | P002 | Healthy | R | R | 65.0 | 1 |
| 4 | P002 | Healthy | R | L | 65.0 | 1 |

- Record numbers must be unique. A header row is optional.
- Group: `ACLR` or `Healthy` (`control` also works). Limbs: `L`/`R` or `Left`/`Right`.
- Trial is optional and defaults to 1. By default, all trials for a participant's limb are pooled. Tick **"Trial numbers are separate sessions"** to summarize each trial on its own (for visits or timepoints).
- The app warns if a participant's group or injured/nondominant limb differs across records.
- LSI = ACLR / uninvolved x 100 (ACLR) or nondominant / dominant x 100 (healthy).

## Naming torque files

Name each file with its **record number** first: `12.csv`, `12_isok60.csv`, `12-mvic.txt`, or `rec12.csv`. A record can have several files (e.g. isometric, 60 deg/s, and 240 deg/s). The task and speed are detected from the data.

## Tracking whose file is whose

- After the key loads, the Files table shows participant, group, limb tested (ACLR / uninvolved / nondominant / dominant), trial, and mass for every file. Rows with no key match are yellow. Double-click `record` to fix a mislabeled file.
- The QC file list and plot title show `Record | Participant | Group | Limb | Trial | Task`.
- Every results table and Excel sheet includes record, participant, limb, and trial.
- **Download labeled files (.zip)** writes a copy of each raw file with a header block (record, participant, group, limb tested and its role, injured/nondominant limb, trial, mass, detected task, sampling rate, original filename). Each copy gets a descriptive filename, e.g. `P001_ACLR_L-inv_T1_isok60_rec012.csv`. Labeled files can be re-uploaded; the record number is read from the header.

## Torque files

- Raw exports go in as-is; you don't need to delete header content by hand. The app handles two layouts:
  - **Named columns** (a row containing `Time` and `Torque`, plus `Angle`/`Position` for isokinetic): any header block above that row is skipped.
  - **No column names**: reading starts at the first row that begins a run of 20+ all-numeric rows. Columns are taken by position, set under *Column positions* in the sidebar (default 1 = time, 2 = torque, 3 = angle). Set these **before** uploading.
- Comma, tab, semicolon, and whitespace delimiters are all detected.
- Sampling rate comes from the Time column. Files below 250 Hz are rejected.
- Task is detected from the data: no angle movement means isometric. For isokinetic files, speed is measured from angular velocity and snapped to the nearest standard speed.

## Workflow

1. **Upload and assign**: load the key file and torque files, then check or edit the Files table and click **Process files**.
2. **QC**: step through files. The plot shows onset (green; orange if set manually), peak (red), the RTD window (green shading), and isovelocity windows (blue/red shading). Select rows to exclude or re-include, with a reason. To move an isometric onset, select one trial, tick "Click the plot to set onset", and click the plot. Every change goes to the QC log.
3. **Results**: LSI, H:Q, limb summary, a wide participant table, and all contractions. **Download Excel workbook** exports every table plus the parameters, QC log, and a methods paragraph.

## Defaults (editable in the sidebar)

| Step | Default | Basis |
|---|---|---|
| Filter | Zero-lag Butterworth, 2nd order per pass (4th overall), 150 Hz | White et al. 2024 gold standard |
| Baseline | Mean of the quietest 250 ms before each contraction, subtracted | White et al. 2024 (offset removed) |
| Onset | First sample at or above 1 Nm above baseline | White et al. 2024 |
| RTD | 0-50, 0-100, 0-150, 0-200 ms from onset, plus 40-160 ms | 40-160 was the most robust window in White et al. 2024 |
| Isokinetic peak / angle at peak | Within +/-10% of target velocity | |
| Average peak, average work | Reps 2 to n | |
| Peak, total work | All reps (a checkbox also excludes rep 1) | |
| H:Q | Flexion / extension, peak and average peak, per limb and speed | |

If the sampling rate is too low for a 150 Hz cutoff (Nyquist), the cutoff is reduced to 80% of Nyquist and the contraction is flagged.

## Reference

White MS, Graham MC, Janatova T, Hawk GS, Thompson KL, Noehren B. Effect of sampling rate, filtering, and torque onset detection on quadriceps rate of torque development and torque steadiness. *Sensors*. 2024;24(13):4250. [doi:10.3390/s24134250](https://doi.org/10.3390/s24134250)

## Details

- **Files:** `app.R` (the app), `key_template.csv` (key file layout), and `example-data/` (simulated files and key)
- **Author:** Christopher Kuenze, PhD, ATC, FNATA
- **Last updated:** November 2026
