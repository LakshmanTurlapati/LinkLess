I’ve reviewed your markdown file, and it’s actually a fantastic post-mortem of the issue. You’ve clearly articulated the problem, why the initial approach failed, and why the final approach succeeded, backed by solid numerical evidence.

To make this documentation even better, I have refined the formatting, converted your inline formulas into formal mathematical notation for better readability, and strategically inserted image tags where visual aids would help a future developer (or yourself) instantly grasp the geometric concepts being discussed.

Here is the improved and corrected markdown file:

---

# L-Ascender Loop Compression: Post-Mortem and Implementation Plan

## Background

The LinkLess "Le" submark logo features a calligraphic letter "L" whose ascender forms a self-crossing loop—a tight, elongated teardrop shape where the stroke crosses over itself. When the pen draws upward, curves left at the peak, and returns downward, the two arms of the stroke overlap visually.

The `misc/extract_centerline.py` script extracts a single-pixel skeleton (centerline) from the logo PNG, then converts it to an SVG path for the drawing animation in `misc/le-animation.html`. The path is rendered with `stroke-width="9"`, meaning the browser draws a 9-SVG-unit-wide band centered on the path.

## The Problem

The skeleton extraction faithfully traces the center of the thick calligraphic stroke. In the self-crossing loop region, this produces two separate branches (ascending arm and descending arm) whose centerlines are ~68 pixels apart in the source image. After scaling to the 241x273 SVG viewBox, this became ~23 SVG units of separation between the two arms.

With `stroke-width=9`, each arm paints a 9-unit band. For the strokes to visually overlap (cross), the centerlines need to be less than 9 units apart. At 23 units, the two arms had a visible gap of ~14 units between them—nothing like the tight crossing in the original logo.

**Goal:** Reduce the centerline separation from ~23 to 5-8 SVG units so the 9px strokes overlap, forming the tight teardrop that matches the original.

## Round 1 — Sine Envelope (Failed)

### Approach

The first attempt added a `compress_ascender_loop()` function that:

1. Found the peak of the loop (global y-minimum, the topmost point).
2. Identified `stem_x` (the x-coordinate of the vertical stem below the loop).
3. Found the loop entry/exit points (where x returns to `stem_x`).
4. Compressed each point's x-coordinate toward `stem_x` using a sine envelope:



*(where  is 0 at entry, 1 at exit)*



*(where  is 0 at ends, 1 at midpoint)*


5. Used `ASCENDER_LOOP_COMPRESSION = 0.30`, later reduced to 0.08, then 0.03.

### Why It Failed

The sine envelope reaches its maximum (1.0) at the midpoint of the index range, which roughly corresponds to the peak/tip of the loop. This means:

* **At the peak:** Maximum compression (97% at ratio=0.03). The gap collapsed to ~1.7 SVG units—nearly a flat line. The teardrop tip got pinched shut.
* **At the lower/wider sections:** Minimal compression (envelope was only 0.14-0.55). The gap remained 17-24 SVG units—still far too wide for overlap.

The result was the exact opposite of what was needed. The loop is naturally narrowest at the peak and widest in the lower sections. The sine envelope compressed most aggressively where the loop was already narrow, and barely touched the wide parts. This created a distorted, pinched-and-bulging shape instead of a uniformly narrowed teardrop.

### Numerical Evidence (Pre-Fix)

| Loop Region | Index Range | Gap Before | Gap After (sine, r=0.03) |
| --- | --- | --- | --- |
| Lower entry section | 1-10 | 17-24 SVG | 17-24 SVG *(barely changed)* |
| Widest section | 31-36 | ~23 SVG | ~17.6 SVG *(still too wide)* |
| Peak/tip | 51-56 | ~20 SVG | ~1.7 SVG *(collapsed)* |
| Lower exit section | 90-110 | 17-20 SVG | 14-18 SVG *(barely changed)* |

## Round 2 — Uniform Ratio (Fixed)

### Approach

The fix replaced the sine envelope with a uniform compression ratio:

1. Same peak, `stem_x`, and entry/exit detection as before.
2. Compute the viewBox scale factor (~0.3438) that will be applied later.
3. Convert the target gap from SVG units (7.0) back to pre-scale coordinates:


4. Find the maximum distance from `stem_x` across all loop points.
5. Compute a single ratio:


6. Apply this ratio **uniformly** to every point in the loop:



### Why It Works

Every point in the loop is scaled by the same fraction (~0.102). This is equivalent to horizontally squeezing the loop by a constant factor. The proportions of the original teardrop shape are perfectly preserved—points that were farther from the stem move proportionally more than points that were closer. The shape just gets narrower uniformly.

### Numerical Evidence (Post-Fix)

| Loop Region | Index Range | Gap Before | Gap After (uniform, r=0.102) |
| --- | --- | --- | --- |
| Lower entry section | 1-10 | 17-24 SVG | 1.7-2.5 SVG |
| Widest section | 31-36 | ~23 SVG | ~6.9 SVG |
| Peak/tip | 51-56 | ~20 SVG | ~6.1 SVG |
| Lower exit section | 90-110 | 17-20 SVG | 1.7-2.0 SVG |

* With `stroke-width=9`, all sections now overlap (gap < 9 everywhere).
* The widest point is ~6.9 SVG units (target was 7.0).
* Shape proportions match the original teardrop.

## Configuration

The compression is controlled by a single constant in `extract_centerline.py`:

```python
ASCENDER_LOOP_TARGET_GAP = 7.0   # desired SVG-unit gap between ascending/descending strokes

```

* **Lower value** (e.g., 5.0) = tighter overlap, thicker crossing appearance
* **Higher value** (e.g., 8.5) = barely overlapping, thinner crossing
* **9.0 or above** = strokes just touch or separate (no visible crossing)

## Pipeline Summary

The full extraction pipeline (run with `python3 misc/extract_centerline.py`):

1. **Load PNG**, binarize using alpha threshold (128).
2. **Skeletonize** (morphological thinning to 1px centerline).
3. **Prune** short branches (remove spurs < 20px).
4. **Decompose** skeleton into junction-free segments.
5. **Assemble** segments in stroke order (known "Le" topology).
6. **Smooth and simplify**:
* Gaussian filter (sigma=7) for global smoothing.
* Extra Gaussian pass (sigma=18) at junction seams.
* RDP simplification (epsilon=1.8) to reduce point count.
* Chaikin corner-cutting (2 iterations) to re-smooth RDP corners.
* **>>> `compress_ascender_loop()` <<< *(the fix lives here)***


7. **Scale points** to fit 241x273 viewBox with 10px padding.
8. **Convert points** to SVG cubic Bezier path (Catmull-Rom spline fitting).
9. **Write** `le-centerline.svg` for visual verification.

*Note: After running, the printed path `d` attribute is manually (or programmatically) copied into `le-animation.html` for both the `#glow-trail` and `#text-path` elements.*

## Files Changed

| File | Change |
| --- | --- |
| `misc/extract_centerline.py` | Replaced `ASCENDER_LOOP_COMPRESSION` constant with `ASCENDER_LOOP_TARGET_GAP = 7.0`. Rewrote `compress_ascender_loop()` to use uniform ratio instead of sine envelope. |
| `misc/le-animation.html` | Updated `d` attributes for both `#glow-trail` and `#text-path` with regenerated path data. |
| `misc/le-centerline.svg` | Regenerated by the script (verification overlay). |

## Key Lesson

When compressing a shape toward an axis, a **uniform** scaling factor preserves proportions. A spatially-varying envelope (like sine) changes the relative distances between points, distorting the shape. The sine envelope was particularly bad here because its peak aligned with the part of the loop that least needed compression, while leaving the widest sections nearly untouched.

---

Would you like me to help draft a commit message based on this post-mortem, or is there another piece of the project you'd like to look at next?