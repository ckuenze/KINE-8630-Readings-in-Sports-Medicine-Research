# FFT and Filter Explorer

Build a movement signal, add realistic noise, then filter it, and see the effect in the time domain and the frequency domain at the same time.

- **Methods topic:** Frequency-domain analysis and digital filtering
- **Course:** KINE 8630

## Learning objectives

After using this tool, students should be able to:

- Read an FFT magnitude spectrum and identify the dominant frequency of a movement signal and its harmonics.
- Recognize the spectral signatures of common noise sources: narrow powerline interference (60 Hz), band-limited motion artifact (~30–40 Hz), and broadband sensor noise.
- Match a filter type (moving average, low-pass, high-pass, notch) to a noise source and explain the trade-offs.
- Explain how cutoff choice affects signal content, and why a filter that removes noise can also distort the movement signal.

## How to use it

Open `index.html` in a web browser.

1. **Movement signal:** choose running, walking, or a jump landing, and set the stride frequency.
2. **Noise:** turn on powerline hum or motion artifact, and set the level of broadband noise.
3. **Filter:** choose a filter and adjust its cutoff, window, or notch width (Q).

The callouts below the charts describe what each noise source and filter is doing.

## Details

- **File:** `index.html` (standalone; loads Chart.js from cdnjs)
- **Sampling:** 256 Hz over a 2 s window (512-point FFT), so the spectrum extends to the 128 Hz Nyquist frequency.
- **Filters:** Simple teaching implementations (1-pole IIR low-pass and high-pass, biquad notch, centered moving average). These are not the zero-lag Butterworth filters typically used in biomechanics.
- **Data:** All signals are simulated for teaching.
- **Author:** Christopher Kuenze, PhD, ATC, FNATA
- **Last updated:** November 2026
