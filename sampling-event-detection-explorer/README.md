# Sampling and Event Detection Explorer

Three ways undersampling can mislead you: underestimating a sharp peak, missing discrete events, and misreading the frequency of a periodic signal. Change the sampling rate in each mode and watch the failure happen.

- **Methods topic:** Sampling rate selection, event detection, and aliasing
- **Course:** KINE 8630

## Learning objectives

After using this tool, students should be able to:

- Explain why the sampled peak of a brief impact depends on both sampling rate and the timing of samples relative to the event.
- Interpret sampling-rate requirements as a probability of meeting an accuracy criterion, not a single pass/fail threshold.
- Tell apart two failure modes of undersampling: events that disappear (missed beats) and periodic signals that are misread at a lower frequency (aliasing).
- Apply the Nyquist criterion and predict the apparent (aliased) frequency of an undersampled signal.
- Justify a sampling rate for a given outcome and task using published benchmarks.

## Modes

**Impact peak (vGRF).** A simulated impact with adjustable rise time (stiff to soft landing). The probability curve is a Monte Carlo estimate over random sample timing of capturing at least 90% of the true peak, the accuracy criterion used by Renner et al. (2022).

**Heartbeat detection.** A simulated R-wave train with adjustable heart rate and R-wave width. Shows how often every beat is detected at a given sampling rate.

**Aliasing (periodic signal).** A periodic signal with a fundamental and a second harmonic. Compares the true frequency, the Nyquist requirement, and the apparent (aliased) frequency of the samples.

## How to use it

Open `index.html` in a web browser. Choose a mode, adjust the event and sampling sliders, and click **New trial** to re-draw the sample timing.

## Reference

Renner KE, Peebles AT, Socha JJ, Queen RM. The impact of sampling frequency on ground reaction force variables. *J Biomech*. 2022;135:111034. [doi:10.1016/j.jbiomech.2022.111034](https://doi.org/10.1016/j.jbiomech.2022.111034)

## Details

- **File:** `index.html` (standalone; loads Chart.js from cdnjs)
- **Data:** All signals are simulated for teaching, not participant recordings.
- **Author:** Christopher Kuenze, PhD, ATC, FNATA
- **Last updated:** November 2026
