# Example data: simulated ActiGraph 60-s epoch files

Five simulated 7-day hip-worn accelerometer recordings for use with the PA Processing Dashboard. **These are not participant data.** They were generated from scratch to match the ActiLife "Data Scoring Details" 60-s epoch export format.

| File | Profile |
|---|---|
| `SIM-01_high-MVPA_60s-epochs.csv` | Active adult who runs most mornings |
| `SIM-02_low-MVPA_60s-epochs.csv` | Mostly sedentary desk worker |
| `SIM-03_high-MVPA_60s-epochs.csv` | Active adult who does brisk walks twice a day |
| `SIM-04_low-MVPA_60s-epochs.csv` | Lots of light activity, little MVPA |
| `SIM-05_fails-wear-criteria_60s-epochs.csv` | Inconsistent wear; does not meet the 4-day / 1-weekend-day, 10 h/day criteria |

## Protocol

- Device on Wednesday 10/14/2026 at 11:00 AM and collected Wednesday 10/21/2026 at 10:59 AM (10,080 one-minute epochs), so the first and last days are partial.
- Removed for sleep each night (zero counts, inclinometer "off").
- `SIM-05` also contains a 4-hour block of missing epochs, which the dashboard treats as a device-off gap.

## Columns

`date, epoch, axis1, axis2, axis3, vm, steps, inclinometer off, inclinometer standing, inclinometer sitting, inclinometer lying`

Counts are per 60-s epoch, `vm` is the vector magnitude of the three axes, `steps` is steps per minute, and the four inclinometer columns are seconds per epoch in each position (they sum to 60).
