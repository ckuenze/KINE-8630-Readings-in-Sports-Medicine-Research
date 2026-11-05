# Example data

Simulated dynamometer files for use with the tools in this repository. **These are not participant data.** They were generated to match the structure of typical isokinetic dynamometer exports so the tools can be used without sharing real recordings.

## Files

| File | Contraction | Velocity | Sampling rate |
|---|---|---|---|
| `isometric_100Hz.csv` | Isometric | — | 100 Hz |
| `isometric_1000Hz.csv` | Isometric | — | 1000 Hz |
| `isokinetic_60degs_100Hz.csv` | Isokinetic | 60°/s | 100 Hz |
| `isokinetic_60degs_1000Hz.csv` | Isokinetic | 60°/s | 1000 Hz |
| `isokinetic_240degs_100Hz.csv` | Isokinetic | 240°/s | 100 Hz |
| `isokinetic_240degs_1000Hz.csv` | Isokinetic | 240°/s | 1000 Hz |

Each condition is provided at 100 Hz and 1000 Hz, so the same trial can be compared at two sampling rates.

## Format

Comma-separated, one header row.

- **Isometric files:** `Time,Torque`
- **Isokinetic files:** `Time,Torque,Angle`

`Time` is in seconds and `Angle` is the knee angle in degrees (90° = flexed, 0° = full extension). In the isokinetic files, extension torque is positive and flexion torque is negative.
