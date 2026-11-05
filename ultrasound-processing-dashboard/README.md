# Ultrasound Processing Dashboard

Load one or more ultrasound images, calibrate each to real-world units, and measure distance, cross-sectional area, pennation angle, and echo intensity directly on the image. All images and their measurements are summarized in one table.

- **Methods topic:** Musculoskeletal ultrasound image analysis
- **Course:** KINE 8630

## Learning objectives

After using this tool, students should be able to:

- Calibrate an image from a known distance (for example, the depth scale) and explain how calibration error carries into every distance and area measurement.
- Measure muscle thickness, cross-sectional area, and pennation angle, and describe the sources of measurement error in each.
- Explain what echo intensity represents (mean grayscale within a region), and why it depends on device settings, region selection, and depth.
- Compare repeated measurements across images and raters to think about reliability.

## How to use it

Open `index.html` in a web browser.

1. Click **Add Image(s)** and choose PNG or JPG images.
2. **Calibrate** each image: click two points a known distance apart (or drag a line), then enter the real distance. You can also enter a known pixels-per-unit scale.
3. Choose a measurement mode:
   - **Distance:** click two points or drag a line.
   - **Area:** click around the region, then click **Finish Shape**.
   - **Angle:** click two points along a fascicle, then two points along the aponeurosis it inserts into. Pennation angle is the acute angle between the two lines.
   - **Echo Intensity:** drag a rectangle, or use an area shape you've already drawn.
4. **Undo Last** removes the most recent measurement and its drawing. Use **Copy summary as CSV** to export the summary table.

## Example images

No example images are included, because the images available to the course are research data. Use your own images, or images you have permission to use.

## Details

- **File:** `index.html` (standalone, no external libraries)
- **Privacy:** Images stay in your browser and are never uploaded.
- **Accuracy:** Measurements depend on accurate calibration and careful manual tracing. Treat them as estimates, not clinical-grade measurements. Echo intensity is not corrected for depth attenuation.
- **Author:** Christopher Kuenze, PhD, ATC, FNATA
- **Last updated:** November 2026
