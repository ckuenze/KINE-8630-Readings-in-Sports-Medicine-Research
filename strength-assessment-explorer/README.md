# Strength Assessment Explorer

See how acquisition and processing choices change isometric and isokinetic strength outcomes. Adjust sampling rate, filter cutoff, and onset threshold, add powerline interference, and watch peak torque, rate of torque development (RTD), torque steadiness, and H:Q ratios change.

- **Methods topic:** Processing choices in isometric and isokinetic strength testing
- **Course:** KINE 8630

## Learning objectives

After using this tool, students should be able to:

- Explain how sampling rate, low-pass cutoff, and torque onset threshold affect peak torque, early and late RTD, and torque steadiness.
- Explain why early RTD (0–50 ms) is more sensitive to processing choices than peak torque, and how those choices can change the size of a between-group difference.
- Recognize onset detection triggered by baseline noise, and aliased powerline interference at low sampling rates.
- Describe how dynamometer acceleration artifacts and the shrinking isovelocity window affect isokinetic peak torque at higher speeds.
- Compare automated and manual peak selection, and absolute vs. average peak torque across repetitions.

## Tabs

1. **Isometric: Healthy vs. Knee OA.** Two simulated knees processed with the same settings. Includes presets for the White et al. (2024) gold standard (2222 Hz, 150 Hz, 1 Nm) and a typical clinical handheld setup (100 Hz, 10 Hz, 5 Nm).
2. **Isokinetic: 60 / 180 / 300 °/s.** One simulated extension–flexion cycle at three speeds, with peak torque, H:Q ratio, cycle time, and the share of the range of motion at true constant velocity.
3. **Analyze Your Own Data.** Load a CSV or XLSX file (time, torque, and angle for isokinetic files), set the filter and onset threshold, and compare automated and manual peaks.

## Using the example data

The simulated dynamometer files in [`../data/`](../data/) work in the **Analyze Your Own Data** tab. Choose **Isometric** for `isometric_*.csv` or **Isokinetic** for `isokinetic_*.csv`, then load the file. Each condition comes at 100 Hz and 1000 Hz, so you can compare the same trial at two sampling rates.

## Reference

White MS, Graham MC, Janatova T, Hawk GS, Thompson KL, Noehren B. Effect of sampling rate, filtering, and torque onset detection on quadriceps rate of torque development and torque steadiness. *Sensors*. 2024;24(13):4250. [doi:10.3390/s24134250](https://doi.org/10.3390/s24134250)

## Details

- **File:** `index.html` (standalone; loads Chart.js from cdnjs and SheetJS from cdn.sheetjs.com for XLSX files)
- **Data:** The Isometric and Isokinetic tabs use simulated signals, not patient recordings. Uploaded files stay in your browser.
- **Filter:** A zero-lag (forward and backward) 1-pole low-pass, used for teaching. It is not a Butterworth filter.
- **Author:** Christopher Kuenze, PhD, ATC, FNATA
- **Last updated:** November 2026
