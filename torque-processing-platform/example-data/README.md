# Example data: simulated multi-participant torque files

Simulated 1000 Hz knee dynamometer files for practicing with the Torque Processing Platform. **These are not participant data.** They were generated from scratch to look like typical isokinetic dynamometer exports.

## Design

- **4 participants:** P01 and P02 (ACLR), P03 and P04 (Healthy), each with a different body mass.
- **Both limbs** tested, in **2 sessions** (trial 1 and trial 2), for **16 records**.
- **3 files per record (48 files):**
  - `<record>_isom.csv`: isometric knee extension, 3 maximal contractions of 3 s each
  - `<record>_isok60.csv`: isokinetic 60°/s, 5 extension–flexion reps
  - `<record>_isok240.csv`: isokinetic 240°/s, 5 extension–flexion reps
- **`example_key.csv`** links every record to its participant, group, injured or nondominant limb, limb tested, body mass, and session.

The ACLR involved limbs are weaker and slower to develop torque than the uninvolved limbs, and improve somewhat at session 2. Healthy participants are close to symmetric. A few files contain problems worth finding in the QC step.

## How to use them

1. Run the app (see the [platform README](../README.md)).
2. Load `example_key.csv` as the key file.
3. Load all 48 torque files, then click **Process files**.
4. Work through QC, then compare the results with and without **Trial numbers are separate sessions** ticked.

## Format

Comma-separated, one header row, 1000 Hz. Isometric files have `Time,Torque`; isokinetic files have `Time,Torque,Angle`. Time is in seconds, torque in N·m, and angle in degrees (90° = flexed, 0° = full extension). Extension torque is positive and flexion torque is negative.
