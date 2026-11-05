# KINE 8630: Readings in Sports Medicine Research

Interactive tools for **KINE 8630**, a doctoral seminar on contemporary methods in sports medicine research at the University of Virginia.

These tools show what happens to biomechanical data when methodological choices change: sampling rate, filtering, marker placement, gap filling, and data-quality screening. Most are single HTML files that run in a modern web browser, with nothing to install. The Torque Processing Platform is an R Shiny app.

## Tools

| Tool | Methods topic |
|---|---|
| [Sampling and Event Detection Explorer](sampling-event-detection-explorer/) | Sampling rate, peak underestimation, missed events, and aliasing |
| [FFT and Filter Explorer](fft-filter-explorer/) | Frequency-domain analysis, noise sources, and digital filtering |
| [Motion Capture Dashboard](motion-capture-dashboard/) | Marker clusters, joint center methods, gap filling, and data-quality checks |
| [PA Processing Dashboard](pa-processing-dashboard/) | Accelerometer wear-time validation, valid-day criteria, and intensity cutpoints |
| [Strength Assessment Explorer](strength-assessment-explorer/) | Sampling, filtering, and onset choices in isometric and isokinetic strength testing |
| [Torque Processing Platform](torque-processing-platform/) (R Shiny) | Building a standardized, semi-automated processing pipeline (Unit 3 project example) |
| [Ultrasound Processing Dashboard](ultrasound-processing-dashboard/) | Calibrated distance, area, pennation angle, and echo intensity measurement |

## Data

All signals in these tools are simulated for teaching. No participant data are stored in this repository. Simulated isometric and isokinetic dynamometer files, built to match the structure of real lab exports, are in [`data/`](data/). Simulated ActiGraph epoch files for the PA Processing Dashboard are in [`pa-processing-dashboard/example-data/`](pa-processing-dashboard/example-data/), and simulated multi-participant torque files for the Torque Processing Platform are in [`torque-processing-platform/example-data/`](torque-processing-platform/example-data/).

## How to open a tool

1. Click a tool's folder above.
2. Download `index.html` (click the file, then the download button).
3. Open the file in Chrome, Edge, Firefox, or Safari.

For the Torque Processing Platform, download its folder and see its README for how to run it in R.

## About

Created by Christopher Kuenze, PhD, ATC, FNATA, Department of Kinesiology, UVA School of Education and Human Development.
