# Motion Capture Dashboard

Practice three judgment calls behind clean kinematic and kinetic data: where to put markers, how to fill gaps, and when to distrust a trial. Each module works with a simulated walking trial and a simulated countermovement jump.

- **Methods topic:** Marker-based motion capture, gap filling, and data-quality screening
- **Course:** KINE 8630

## Learning objectives

After using this tool, students should be able to:

- Explain why tracking clusters need at least three non-collinear markers, and how cluster geometry and marker noise affect segment orientation error.
- Describe how knee marker misplacement and segment axial-rotation error create kinematic cross-talk (for example, apparent abduction in a knee that only flexes).
- Compare knee joint center methods (single lateral marker, medial and lateral epicondyles, functional) and their sources of error.
- Compare gap-filling methods (linear, natural cubic spline, PCHIP, Akima, smoothing spline) by their error, peak bias, and behavior over long gaps.
- Identify common kinematic and kinetic artifacts (soft-tissue artifact, marker swaps, plate drift, electrical noise, impact ringing, clipping) and the checks that reveal them.
- Use internal consistency checks, such as flight-time vs. impulse jump height and the unloaded-plate baseline, to decide whether a trial is usable.

## Modules

1. **Marker clusters.** Drag markers on a lateral view of the thigh and shank, choose 2–4 markers per segment, and see the resulting orientation error (Monte Carlo over marker noise), the effect on reported knee angles, and three knee joint center methods.
2. **Gaps and splines.** Hide parts of a noisy knee flexion trace and compare five gap-filling methods against the true movement, with optional zero-lag Butterworth filtering afterward.
3. **Data quality.** Turn on kinematic and kinetic problems (one at a time or as preset scenarios) and see how they change the curves, the reported outcomes, and a set of quality checks with a usable / check / do-not-use verdict.

## How to use it

Open `index.html` in a web browser. Choose **Walking** or **Countermovement jump** at the top, then work through the three tabs.

## Details

- **File:** `index.html` (standalone; loads Google Fonts; supports dark mode)
- **Data:** All curves are simulated, schematic data shaped like typical walking and countermovement jump trials for a 75 kg adult, not measurements from a person.
- **Thresholds:** Quality-check thresholds are teaching guides. Use your lab's own criteria.
- **Author:** Christopher Kuenze, PhD, ATC, FNATA
- **Last updated:** November 2026
