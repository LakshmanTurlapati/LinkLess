#!/usr/bin/env python3
"""
Extract centerline stroke from the 'Le' submark logo PNG and produce
an SVG path suitable for the drawing animation in le-animation.html.

Strategy: Skeletonize, decompose into junction-free segments, then
assemble segments in the known stroke order using the "Le" topology.

Usage:
    python3 misc/extract_centerline.py
"""

import os
import sys
import numpy as np
from PIL import Image
from skimage.morphology import skeletonize
from scipy.ndimage import gaussian_filter1d, label as ndlabel

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
ALPHA_THRESHOLD = 128
PRUNE_MIN_LENGTH = 20
GAUSSIAN_SIGMA = 7
RDP_EPSILON = 1.8
CATMULL_ROM_ALPHA = 0.5
ASCENDER_LOOP_TARGET_GAP = 6.0   # SVG-unit gap at widest point of loop
LOOP_TRANSITION_FRAC = 0.125     # fraction of loop for each transition zone
STEM_SAMPLE_HEIGHT_PX = 55       # px window below loop for median stem_x
LOCAL_SMOOTH_SIGMA = 2.5         # Gaussian sigma for post-compression cleanup

TARGET_VB_WIDTH = 241
TARGET_VB_HEIGHT = 273
PADDING = 10


# ---------------------------------------------------------------------------
# Utilities
# ---------------------------------------------------------------------------
def _perpendicular_distance(point, line_start, line_end):
    dx = line_end[0] - line_start[0]
    dy = line_end[1] - line_start[1]
    if dx == 0 and dy == 0:
        return np.hypot(point[0] - line_start[0], point[1] - line_start[1])
    t = ((point[0] - line_start[0]) * dx + (point[1] - line_start[1]) * dy) / (dx * dx + dy * dy)
    t = max(0, min(1, t))
    proj_x = line_start[0] + t * dx
    proj_y = line_start[1] + t * dy
    return np.hypot(point[0] - proj_x, point[1] - proj_y)


def rdp_simplify(points, epsilon):
    if len(points) <= 2:
        return points
    dmax = 0
    idx = 0
    for i in range(1, len(points) - 1):
        d = _perpendicular_distance(points[i], points[0], points[-1])
        if d > dmax:
            dmax = d
            idx = i
    if dmax > epsilon:
        left = rdp_simplify(points[:idx + 1], epsilon)
        right = rdp_simplify(points[idx:], epsilon)
        return left[:-1] + right
    else:
        return [points[0], points[-1]]


def chaikin_subdivide(points, iterations=2):
    """Chaikin corner-cutting: each iteration replaces edge AB with two points
    at 25% and 75% positions.  Endpoints are kept fixed.  Two iterations
    reduce a 90-degree corner to ~22 degrees."""
    pts = list(points)
    for _ in range(iterations):
        if len(pts) < 3:
            break
        new = [pts[0]]
        for i in range(len(pts) - 1):
            ax, ay = pts[i]
            bx, by = pts[i + 1]
            new.append((0.75 * ax + 0.25 * bx, 0.75 * ay + 0.25 * by))
            new.append((0.25 * ax + 0.75 * bx, 0.25 * ay + 0.75 * by))
        new.append(pts[-1])
        pts = new
    return pts


def _smoothstep(t):
    """Hermite smoothstep: 0 at t=0, 1 at t=1, zero derivative at both ends."""
    t = max(0.0, min(1.0, t))
    return t * t * (3.0 - 2.0 * t)


def compress_ascender_loop(points, target_gap_svg=ASCENDER_LOOP_TARGET_GAP):
    """Compress the L-ascender loop horizontally toward the stem (v3).

    v3 improvements over v2:
    - Robust stem_x via median of a sample window (not single-point min)
    - Smoothstep transition zones at entry/exit (no curvature discontinuity)
    - Local Gaussian cleanup on the loop region after compression

    Args:
        points: list of (x, y) tuples (already in SVG x/y space, i.e.
                col=x, row=y after the smooth_and_simplify conversion).
        target_gap_svg: desired gap in SVG units between the two strokes
                at the widest point of the loop (default 6.8).

    Returns:
        New list of (x, y) tuples with the loop section compressed.
    """
    if len(points) < 20:
        return points

    # 1. Find the peak -- the global y-minimum (topmost point of the "L").
    peak_idx = min(range(len(points)), key=lambda i: points[i][1])
    peak_x, peak_y = points[peak_idx]

    # 2. Robust stem_x via median of points in a y-based sample window below the loop.
    #    Collect x-values from points after the peak whose y is within
    #    STEM_SAMPLE_HEIGHT_PX of the peak -- these are the descent stroke
    #    where the loop merges back into the stem.
    stem_y_hi = peak_y + STEM_SAMPLE_HEIGHT_PX
    stem_xs = [points[i][0] for i in range(peak_idx + 1, len(points))
               if peak_y + 10 < points[i][1] <= stem_y_hi]
    if len(stem_xs) < 3:
        # Fallback: use a fixed index window
        descent_lo = min(peak_idx + 10, len(points) - 1)
        descent_hi = min(peak_idx + 50, len(points))
        if descent_hi <= descent_lo:
            print("  [compress_ascender_loop] Not enough points after peak, skipping.")
            return points
        stem_xs = [points[i][0] for i in range(descent_lo, descent_hi)]
    stem_x = float(np.median(stem_xs))

    # 3. Walk backward from peak to find entry_idx where x returns to stem_x.
    entry_idx = peak_idx
    for i in range(peak_idx - 1, -1, -1):
        if points[i][0] <= stem_x:
            entry_idx = i
            break

    # 4. Walk forward from peak to find exit_idx where x returns to stem_x.
    exit_idx = peak_idx
    for i in range(peak_idx + 1, len(points)):
        if points[i][0] <= stem_x:
            exit_idx = i
            break

    if entry_idx == peak_idx or exit_idx == peak_idx:
        print("  [compress_ascender_loop] Could not find loop boundaries, skipping.")
        return points

    # 4b. Extend exit to cover the full overlap zone.
    #     The ascending arm extends down to entry_idx's y-level. Points on the
    #     descending arm below exit_idx still have x != stem_x and create a
    #     visible gap if left uncompressed. Extend exit_idx until the
    #     descending arm reaches the same y-depth as the ascending entry.
    entry_y = points[entry_idx][1]
    orig_exit_idx = exit_idx
    for i in range(exit_idx + 1, len(points)):
        if points[i][1] >= entry_y:
            exit_idx = i
            break
    if exit_idx != orig_exit_idx:
        print(f"  [compress_ascender_loop] Extended exit: {orig_exit_idx} -> {exit_idx} "
              f"(matching entry y={entry_y:.0f})")

    loop_len = exit_idx - entry_idx
    if loop_len < 5:
        print("  [compress_ascender_loop] Loop too short, skipping.")
        return points

    # Measure width before compression
    loop_xs = [points[i][0] for i in range(entry_idx, exit_idx + 1)]
    width_before = max(loop_xs) - min(loop_xs)

    # 5. Compute the scale factor that will be applied later (viewbox fitting).
    all_xs = [p[0] for p in points]
    all_ys = [p[1] for p in points]
    src_w = max(all_xs) - min(all_xs)
    src_h = max(all_ys) - min(all_ys)
    uw = TARGET_VB_WIDTH - 2 * PADDING
    uh = TARGET_VB_HEIGHT - 2 * PADDING
    scale = min(uw / src_w, uh / src_h) if src_w > 0 and src_h > 0 else 1.0

    target_gap_prescale = target_gap_svg / scale
    max_dist = max(points[i][0] - stem_x for i in range(entry_idx, exit_idx + 1))

    if max_dist < 1.0:
        print("  [compress_ascender_loop] Loop max distance too small, skipping.")
        return points

    # Uniform ratio: every point keeps this fraction of its distance from stem_x.
    ratio = target_gap_prescale / max_dist
    ratio = min(ratio, 1.0)  # never expand

    # 6. Smoothstep transition zones + uniform core compression.
    trans_len = max(3, int(loop_len * LOOP_TRANSITION_FRAC))
    result = list(points)
    for i in range(entry_idx, exit_idx + 1):
        x, y = points[i]
        # Determine blend factor (0 = no compression, 1 = full compression)
        dist_from_entry = i - entry_idx
        dist_from_exit = exit_idx - i
        if dist_from_entry < trans_len:
            blend = _smoothstep(dist_from_entry / trans_len)
        elif dist_from_exit < trans_len:
            blend = _smoothstep(dist_from_exit / trans_len)
        else:
            blend = 1.0  # core zone: full compression
        effective_ratio = 1.0 - blend * (1.0 - ratio)
        new_x = stem_x + (x - stem_x) * effective_ratio
        result[i] = (new_x, y)

    # 7. Local Gaussian cleanup on the compressed region only.
    #    Do NOT extend past entry/exit boundaries -- blending with
    #    uncompressed neighbors would undo compression near the edges.
    loop_slice = slice(entry_idx,
                       min(len(result), exit_idx + 1))
    indices = list(range(*loop_slice.indices(len(result))))
    if len(indices) > 3:
        loop_xs_arr = np.array([result[i][0] for i in indices])
        loop_xs_smooth = gaussian_filter1d(loop_xs_arr, sigma=LOCAL_SMOOTH_SIGMA)
        for j, i in enumerate(indices):
            result[i] = (float(loop_xs_smooth[j]), result[i][1])

    # Measure width after
    loop_xs_after = [result[i][0] for i in range(entry_idx, exit_idx + 1)]
    width_after = max(loop_xs_after) - min(loop_xs_after)
    print(f"  [compress_ascender_loop] Loop idx {entry_idx}-{exit_idx} "
          f"(peak={peak_idx}), stem_x={stem_x:.1f} (median)")
    print(f"  [compress_ascender_loop] Width: {width_before:.1f} -> {width_after:.1f} "
          f"(uniform ratio={ratio:.3f}, target_gap={target_gap_svg} SVG units)")
    print(f"  [compress_ascender_loop] Transition zones: {trans_len} pts each, "
          f"local smooth sigma={LOCAL_SMOOTH_SIGMA}")

    return result


def get_8_neighbors(skeleton, r, c):
    neighbors = []
    for dr in [-1, 0, 1]:
        for dc in [-1, 0, 1]:
            if dr == 0 and dc == 0:
                continue
            nr, nc = r + dr, c + dc
            if 0 <= nr < skeleton.shape[0] and 0 <= nc < skeleton.shape[1]:
                if skeleton[nr, nc]:
                    neighbors.append((nr, nc))
    return neighbors


# ---------------------------------------------------------------------------
# Image processing
# ---------------------------------------------------------------------------
def load_and_binarize(image_path, threshold=ALPHA_THRESHOLD):
    img = Image.open(image_path).convert("RGBA")
    alpha = np.array(img)[:, :, 3]
    binary = alpha > threshold
    print(f"  Image size: {img.size}, Stroke pixels: {binary.sum()}")
    return binary


def extract_skeleton(binary):
    skeleton = skeletonize(binary)
    print(f"  Skeleton pixels: {skeleton.sum()}")
    return skeleton


def prune_short_branches(skeleton, min_length=PRUNE_MIN_LENGTH):
    skeleton = skeleton.copy()
    changed = True
    iterations = 0
    while changed and iterations < 50:
        changed = False
        iterations += 1
        coords = np.argwhere(skeleton)
        junction_set = set()
        endpoints = []
        for r, c in coords:
            n = len(get_8_neighbors(skeleton, r, c))
            if n == 1:
                endpoints.append((r, c))
            elif n >= 3:
                junction_set.add((r, c))
        for ep in endpoints:
            branch = [ep]
            current = ep
            visited = {ep}
            while True:
                nbrs = [n for n in get_8_neighbors(skeleton, current[0], current[1]) if n not in visited]
                if not nbrs:
                    break
                if len(nbrs) == 1:
                    nxt = nbrs[0]
                    branch.append(nxt)
                    visited.add(nxt)
                    if nxt in junction_set:
                        if len(branch) < min_length:
                            for px in branch[:-1]:
                                skeleton[px[0], px[1]] = False
                            changed = True
                        break
                    current = nxt
                else:
                    if len(branch) < min_length:
                        for px in branch[:-1]:
                            skeleton[px[0], px[1]] = False
                        changed = True
                    break
    print(f"  After pruning: {skeleton.sum()} pixels")
    return skeleton


# ---------------------------------------------------------------------------
# Decompose skeleton into segments between junctions
# ---------------------------------------------------------------------------
def decompose_skeleton(skeleton):
    """Decompose skeleton into junction-free segments.

    Returns:
        junctions: set of (row, col) junction pixels (3+ neighbors)
        segments: list of ordered pixel lists, each connecting two
                  junctions or a junction and an endpoint
    """
    coords = np.argwhere(skeleton)

    # Find junctions and endpoints
    junctions = set()
    endpoints = set()
    for r, c in coords:
        n = len(get_8_neighbors(skeleton, r, c))
        if n >= 3:
            junctions.add((int(r), int(c)))
        elif n == 1:
            endpoints.add((int(r), int(c)))

    print(f"  Junctions: {len(junctions)}, Endpoints: {len(endpoints)}")

    # Cluster nearby junctions (within 8px) into junction groups
    # 8px is needed because the e-crossing junctions span ~6px
    junction_list = sorted(junctions)
    junction_clusters = []  # list of sets
    assigned = {}  # pixel -> cluster_id

    for jp in junction_list:
        # Check if close to an existing cluster
        merged = False
        for ci, cluster in enumerate(junction_clusters):
            for cp in cluster:
                if abs(jp[0] - cp[0]) <= 8 and abs(jp[1] - cp[1]) <= 8:
                    cluster.add(jp)
                    assigned[jp] = ci
                    merged = True
                    break
            if merged:
                break
        if not merged:
            assigned[jp] = len(junction_clusters)
            junction_clusters.append({jp})

    # Add non-junction skeleton pixels between clustered junctions to the cluster
    # (pixels with 2 neighbors that are between two junction pixels)
    for ci, cluster in enumerate(junction_clusters):
        expanded = set(cluster)
        for _ in range(5):  # expand a few times
            new_pixels = set()
            for px in expanded:
                for nbr in get_8_neighbors(skeleton, px[0], px[1]):
                    nb = (int(nbr[0]), int(nbr[1]))
                    if nb not in expanded and nb not in endpoints:
                        # Check if this pixel is "between" two cluster pixels
                        nbr_nbrs = get_8_neighbors(skeleton, nb[0], nb[1])
                        in_cluster = sum(1 for nn in nbr_nbrs if (int(nn[0]), int(nn[1])) in expanded)
                        if in_cluster >= 2:
                            new_pixels.add(nb)
            if not new_pixels:
                break
            expanded |= new_pixels
        junction_clusters[ci] = expanded

    # Build a set of all junction-zone pixels
    junction_zone = set()
    pixel_to_cluster = {}
    for ci, cluster in enumerate(junction_clusters):
        for px in cluster:
            junction_zone.add(px)
            pixel_to_cluster[px] = ci

    print(f"  Junction clusters: {len(junction_clusters)}")
    for ci, cluster in enumerate(junction_clusters):
        center = (sum(p[0] for p in cluster) / len(cluster),
                  sum(p[1] for p in cluster) / len(cluster))
        print(f"    Cluster {ci}: {len(cluster)} pixels, center ~({center[0]:.0f},{center[1]:.0f})")

    # Walk segments: start from each junction-zone boundary pixel and walk
    # until hitting another junction zone or endpoint
    segments = []
    walked = set()  # track walked non-junction pixels

    # Find all "exit points" from each junction zone - pixels just outside
    # the zone that are neighbors of zone pixels
    exit_points = []
    for px in junction_zone:
        for nbr in get_8_neighbors(skeleton, px[0], px[1]):
            nb = (int(nbr[0]), int(nbr[1]))
            if nb not in junction_zone:
                # nb is an exit point from this junction zone
                ci = pixel_to_cluster.get(px, -1)
                exit_points.append((nb, ci, px))  # (exit_pixel, cluster_id, zone_pixel)

    # Also start from endpoints
    for ep in endpoints:
        exit_points.append((ep, -1, None))

    for start_px, start_cluster, zone_px in exit_points:
        if start_px in walked:
            continue

        # Walk from start_px
        seg = [start_px]
        walked.add(start_px)
        current = start_px

        while True:
            nbrs = get_8_neighbors(skeleton, current[0], current[1])
            candidates = [(int(n[0]), int(n[1])) for n in nbrs
                         if (int(n[0]), int(n[1])) not in walked and
                            (int(n[0]), int(n[1])) not in junction_zone]

            if not candidates:
                # Check if we've reached a junction zone or endpoint
                break

            if len(candidates) == 1:
                nxt = candidates[0]
            else:
                # At a fork outside junction zone - shouldn't happen after pruning
                # Pick the one most aligned with current direction
                if len(seg) >= 2:
                    tang = (seg[-1][0] - seg[-2][0], seg[-1][1] - seg[-2][1])
                else:
                    tang = (0, 0)
                best = candidates[0]
                best_dot = -999
                for c in candidates:
                    d = (c[0] - current[0], c[1] - current[1])
                    dot = d[0] * tang[0] + d[1] * tang[1]
                    if dot > best_dot:
                        best_dot = dot
                        best = c
                nxt = best

            seg.append(nxt)
            walked.add(nxt)
            current = nxt

        # Determine what this segment connects to at each end
        # Start end: which junction cluster (start_cluster) or endpoint
        # End end: check neighbors of current for junction zone pixels
        end_cluster = -1
        end_zone_px = None
        for nbr in get_8_neighbors(skeleton, current[0], current[1]):
            nb = (int(nbr[0]), int(nbr[1]))
            if nb in junction_zone:
                end_cluster = pixel_to_cluster.get(nb, -1)
                end_zone_px = nb
                break

        # Also check if current is an endpoint
        is_start_ep = start_px in endpoints
        is_end_ep = current in endpoints

        if len(seg) >= 2:  # Only keep meaningful segments
            segments.append({
                'pixels': seg,
                'start': seg[0],
                'end': seg[-1],
                'start_cluster': start_cluster if not is_start_ep else 'ep',
                'end_cluster': end_cluster if not is_end_ep else 'ep',
                'start_zone_px': zone_px,
                'end_zone_px': end_zone_px,
                'length': len(seg),
            })

    print(f"\n  Segments found: {len(segments)}")
    for i, s in enumerate(segments):
        print(f"    Seg {i}: {s['length']:4d} px, "
              f"cluster {s['start_cluster']} ({s['start']}) -> "
              f"cluster {s['end_cluster']} ({s['end']})")

    return junction_clusters, segments, endpoints


def build_path_from_segments(junction_clusters, segments, endpoints):
    """Assemble segments in the correct order for the "Le" stroke.

    The known topology (in image coordinates, row=y down, col=x right):

    EP(707,425) --right--> TailJunction --up--> AscBot --up--> AscTop
    --left--> Peak --right--> AscTop --down--> AscBot --left--> TailJunction
    --down--> TailBottom --up--> TailJunction --right--> ECross
    --up--> ETop --down--> ECross --right--> EP(896,1078)

    Junction clusters (approximate centers):
    - AscTop: ~(591, 568) - cluster with junction pixels at (591,568), (591,569), (592,568)
    - AscBot: ~(642, 560) - single junction at (642,560)
    - TailJunction: ~(987, 536) - cluster with (986,536), (987,535-537)
    - TailTip: ~(1001, 510) - single junction at (1001,510)
    - ECross: ~(899, 845) - cluster with (898-900, 841-847)
    """
    # Identify junction clusters by their approximate locations
    cluster_names = {}
    for ci, cluster in enumerate(junction_clusters):
        center_r = sum(p[0] for p in cluster) / len(cluster)
        center_c = sum(p[1] for p in cluster) / len(cluster)

        if center_r < 600 and center_c < 580:
            cluster_names[ci] = 'asc_top'
        elif 630 < center_r < 660 and center_c < 570:
            cluster_names[ci] = 'asc_bot'
        elif 980 < center_r < 1000 and 530 < center_c < 545:
            cluster_names[ci] = 'tail_junc'
        elif 995 < center_r < 1010 and 500 < center_c < 520:
            cluster_names[ci] = 'tail_tip'
        elif 890 < center_r < 910 and 835 < center_c < 855:
            cluster_names[ci] = 'e_cross'
        else:
            cluster_names[ci] = f'unknown_{ci}'

    print("\n  Cluster identification:")
    for ci, name in sorted(cluster_names.items()):
        cluster = junction_clusters[ci]
        center_r = sum(p[0] for p in cluster) / len(cluster)
        center_c = sum(p[1] for p in cluster) / len(cluster)
        print(f"    Cluster {ci} ({name}): center ({center_r:.0f},{center_c:.0f})")

    # Build a lookup: for each (start_cluster, end_cluster), list matching segments
    seg_lookup = {}
    for i, s in enumerate(segments):
        sc = s['start_cluster']
        ec = s['end_cluster']
        # Convert cluster IDs to names
        sc_name = cluster_names.get(sc, sc) if isinstance(sc, int) else sc
        ec_name = cluster_names.get(ec, ec) if isinstance(ec, int) else ec
        key = (sc_name, ec_name)
        rev_key = (ec_name, sc_name)
        seg_lookup.setdefault(key, []).append((i, False))  # (seg_index, reversed)
        seg_lookup.setdefault(rev_key, []).append((i, True))

    print("\n  Segment connectivity:")
    for key, segs in sorted(seg_lookup.items()):
        for si, rev in segs:
            s = segments[si]
            print(f"    {key[0]} -> {key[1]}: seg {si} ({s['length']} px){' (rev)' if rev else ''}")

    # Now define the stroke order based on actual segment connectivity:
    # EP(707,425) -> asc_bot -> asc_top -> [loop] -> asc_top -> asc_bot
    # -> tail_junc -> tail_tip -> [curl] -> tail_tip -> tail_junc
    # -> e_cross -> [e loop] -> e_cross -> EP(896,1078)
    stroke_order = [
        ('ep', 'asc_bot'),            # EP -> ascender bottom junction
        ('asc_bot', 'asc_top'),       # up the stem
        ('asc_top', 'asc_top'),       # the L-ascender loop (up to peak and back)
        ('asc_top', 'asc_bot'),       # back down (same stem, reused segment reversed)
        ('asc_bot', 'tail_junc'),     # down to tail junction
        ('tail_junc', 'tail_tip'),    # to tail tip junction
        ('tail_tip', 'tail_tip'),     # the tail curl loop
        ('tail_tip', 'tail_junc'),    # back up to tail junction
        ('tail_junc', 'e_cross'),     # rightward to e crossing
        ('e_cross', 'e_cross'),       # the e loop
        ('e_cross', 'ep'),            # exit to endpoint
    ]

    # For each connection in the stroke order, find and consume the matching segment.
    # Some segments are traversed twice (the pen crosses over itself), so we track
    # usage count rather than a simple used/unused flag.
    seg_usage = {}  # seg_index -> number of times used
    full_path = []
    junction_seam_indices = []  # indices in full_path where junction bridges were inserted

    for step_i, (from_name, to_name) in enumerate(stroke_order):
        key = (from_name, to_name)
        candidates = seg_lookup.get(key, [])

        # Prefer unused segments, but allow reuse if no unused ones exist
        unused = [(si, rev) for si, rev in candidates if seg_usage.get(si, 0) == 0]
        available = unused if unused else candidates

        if not available:
            print(f"\n  WARNING: No segment found for step {step_i}: {from_name} -> {to_name}")
            continue

        # Pick the longest available segment (prefer the main loop over tiny stubs)
        available.sort(key=lambda x: segments[x[0]]['length'], reverse=True)
        si, rev = available[0]
        seg_usage[si] = seg_usage.get(si, 0) + 1

        seg = segments[si]
        pixels = list(seg['pixels'])
        if rev:
            pixels = pixels[::-1]

        # Add to full path, bridging junction zone gaps with interpolation
        if full_path and pixels:
            last = full_path[-1]
            first = pixels[0]
            dist = np.hypot(last[0] - first[0], last[1] - first[1])
            if dist < 2:
                full_path.extend(pixels[1:])
            else:
                # Cubic Hermite bridge across the junction zone gap
                # -- tangent-aware interpolation eliminates C0 direction discontinuities
                TANG_LOOKBACK = 10
                # Tangent at the end of the previous segment
                n_prev = min(TANG_LOOKBACK, len(full_path))
                if n_prev >= 2:
                    t0r = full_path[-1][0] - full_path[-n_prev][0]
                    t0c = full_path[-1][1] - full_path[-n_prev][1]
                else:
                    t0r, t0c = first[0] - last[0], first[1] - last[1]
                # Tangent at the start of the next segment
                n_next = min(TANG_LOOKBACK, len(pixels))
                if n_next >= 2:
                    t1r = pixels[n_next - 1][0] - pixels[0][0]
                    t1c = pixels[n_next - 1][1] - pixels[0][1]
                else:
                    t1r, t1c = first[0] - last[0], first[1] - last[1]
                # Normalize tangents and scale by gap distance for natural curvature
                mag0 = np.hypot(t0r, t0c) or 1.0
                mag1 = np.hypot(t1r, t1c) or 1.0
                t0r, t0c = t0r / mag0 * dist, t0c / mag0 * dist
                t1r, t1c = t1r / mag1 * dist, t1c / mag1 * dist
                # Sample the Hermite curve (1.5x gap distance for denser sampling)
                num_steps = max(3, int(round(dist * 1.5)))
                bridge = []
                for k in range(1, num_steps):
                    t = k / num_steps
                    t2, t3 = t * t, t * t * t
                    h00 = 2*t3 - 3*t2 + 1
                    h10 = t3 - 2*t2 + t
                    h01 = -2*t3 + 3*t2
                    h11 = t3 - t2
                    br = h00*last[0] + h10*t0r + h01*first[0] + h11*t1r
                    bc = h00*last[1] + h10*t0c + h01*first[1] + h11*t1c
                    bridge.append((int(round(br)), int(round(bc))))
                seam_center = len(full_path) + len(bridge) // 2
                junction_seam_indices.append(seam_center)
                full_path.extend(bridge)
                full_path.extend(pixels)
        else:
            full_path.extend(pixels)

        print(f"  Step {step_i}: {from_name} -> {to_name}: seg {si} "
              f"({seg['length']} px, {'rev' if rev else 'fwd'}, "
              f"use #{seg_usage[si]}), path now {len(full_path)} px")

    unused = [i for i in range(len(segments)) if seg_usage.get(i, 0) == 0]
    if unused:
        print(f"\n  Unused segments: {unused}")
        for i in unused:
            s = segments[i]
            sc_name = cluster_names.get(s['start_cluster'], s['start_cluster'])
            ec_name = cluster_names.get(s['end_cluster'], s['end_cluster'])
            print(f"    Seg {i}: {sc_name} -> {ec_name}, {s['length']} px")

    print(f"\n  Total path: {len(full_path)} pixels")
    print(f"  Junction seam indices: {junction_seam_indices}")
    return full_path, junction_seam_indices


# ---------------------------------------------------------------------------
# Smoothing and bezier conversion
# ---------------------------------------------------------------------------
def smooth_and_simplify(ordered, junction_seam_indices=None, sigma=GAUSSIAN_SIGMA, epsilon=RDP_EPSILON):
    pts = np.array(ordered, dtype=float)
    # First pass: global Gaussian smoothing
    pts[:, 0] = gaussian_filter1d(pts[:, 0], sigma=sigma)
    pts[:, 1] = gaussian_filter1d(pts[:, 1], sigma=sigma)
    # Second pass: targeted extra smoothing at junction seams
    if junction_seam_indices:
        JUNC_SIGMA = 18
        JUNC_WINDOW = 50
        for idx in junction_seam_indices:
            lo = max(0, idx - JUNC_WINDOW)
            hi = min(len(pts), idx + JUNC_WINDOW + 1)
            if hi - lo < 5:
                continue
            pts[lo:hi, 0] = gaussian_filter1d(pts[lo:hi, 0], sigma=JUNC_SIGMA)
            pts[lo:hi, 1] = gaussian_filter1d(pts[lo:hi, 1], sigma=JUNC_SIGMA)
        print(f"  Applied targeted smoothing at {len(junction_seam_indices)} junction seams")
    xy = [(float(p[1]), float(p[0])) for p in pts]
    simplified = rdp_simplify(xy, epsilon)
    print(f"  RDP simplified to {len(simplified)} points")
    # Chaikin corner-cutting to smooth angular artifacts left by RDP
    smoothed = chaikin_subdivide(simplified, iterations=2)
    print(f"  After Chaikin subdivision: {len(smoothed)} points")
    smoothed = compress_ascender_loop(smoothed, target_gap_svg=ASCENDER_LOOP_TARGET_GAP)
    return smoothed


def catmull_rom_to_bezier(p0, p1, p2, p3, alpha=CATMULL_ROM_ALPHA):
    def tj(ti, pi, pj):
        d = ((pj[0]-pi[0])**2 + (pj[1]-pi[1])**2) ** 0.5
        return ti + d ** alpha
    t0 = 0
    t1 = tj(t0, p0, p1)
    t2 = tj(t1, p1, p2)
    t3 = tj(t2, p2, p3)
    if abs(t1-t0)<1e-10 or abs(t2-t1)<1e-10 or abs(t3-t2)<1e-10:
        return p1, p2
    d1x = (p1[0]-p0[0])/(t1-t0) - (p2[0]-p0[0])/(t2-t0) + (p2[0]-p1[0])/(t2-t1)
    d1y = (p1[1]-p0[1])/(t1-t0) - (p2[1]-p0[1])/(t2-t0) + (p2[1]-p1[1])/(t2-t1)
    d2x = (p2[0]-p1[0])/(t2-t1) - (p3[0]-p1[0])/(t3-t1) + (p3[0]-p2[0])/(t3-t2)
    d2y = (p2[1]-p1[1])/(t2-t1) - (p3[1]-p1[1])/(t3-t1) + (p3[1]-p2[1])/(t3-t2)
    sl = t2 - t1
    return (p1[0]+d1x*sl/3, p1[1]+d1y*sl/3), (p2[0]-d2x*sl/3, p2[1]-d2y*sl/3)


def points_to_svg_path(points):
    if len(points) < 2:
        return ""
    parts = [f"M {points[0][0]:.1f} {points[0][1]:.1f}"]
    if len(points) == 2:
        parts.append(f"L {points[1][0]:.1f} {points[1][1]:.1f}")
        return "\n           ".join(parts)
    gs = (2*points[0][0]-points[1][0], 2*points[0][1]-points[1][1])
    ge = (2*points[-1][0]-points[-2][0], 2*points[-1][1]-points[-2][1])
    ext = [gs] + points + [ge]
    for i in range(1, len(ext)-2):
        cp1, cp2 = catmull_rom_to_bezier(ext[i-1], ext[i], ext[i+1], ext[i+2])
        parts.append(f"C {cp1[0]:.1f} {cp1[1]:.1f}, {cp2[0]:.1f} {cp2[1]:.1f}, {ext[i+1][0]:.1f} {ext[i+1][1]:.1f}")
    return "\n           ".join(parts)


def scale_to_viewbox(points, target_w=TARGET_VB_WIDTH, target_h=TARGET_VB_HEIGHT, padding=PADDING):
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    min_x, max_x = min(xs), max(xs)
    min_y, max_y = min(ys), max(ys)
    src_w = max_x - min_x
    src_h = max_y - min_y
    if src_w == 0 or src_h == 0:
        return points, f"0 0 {target_w} {target_h}"
    uw = target_w - 2*padding
    uh = target_h - 2*padding
    scale = min(uw/src_w, uh/src_h)
    sw = src_w * scale
    sh = src_h * scale
    ox = padding + (uw - sw) / 2
    oy = padding + (uh - sh) / 2
    scaled = [((x-min_x)*scale+ox, (y-min_y)*scale+oy) for x,y in points]
    vb = f"0 0 {target_w} {target_h}"
    print(f"  Scale: {scale:.4f}, Offset: ({ox:.1f},{oy:.1f})")
    return scaled, vb


def write_svg(path_d, viewbox, output_path, image_path=None):
    overlay = ""
    if image_path and os.path.exists(image_path):
        overlay = f'\n  <image href="{os.path.basename(image_path)}" x="0" y="0" width="241" height="273" opacity="0.25" preserveAspectRatio="xMidYMid meet"/>'
    svg = f'''<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"
     viewBox="{viewbox}" width="500" height="500" style="background: #f8f9fa">{overlay}
  <path d="{path_d}"
        fill="none" stroke="#0f1229" stroke-width="9"
        stroke-linecap="round" stroke-linejoin="round"/>
</svg>
'''
    with open(output_path, 'w') as f:
        f.write(svg)
    print(f"  Written: {output_path}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    image_path = os.path.join(script_dir, "Submark - No BG.png")
    svg_output = os.path.join(script_dir, "le-centerline.svg")

    if not os.path.exists(image_path):
        print(f"ERROR: Cannot find {image_path}")
        sys.exit(1)

    print("Step 1: Load and binarize")
    binary = load_and_binarize(image_path)

    print("\nStep 2: Skeletonize")
    skeleton = extract_skeleton(binary)

    print("\nStep 3: Prune short branches")
    skeleton = prune_short_branches(skeleton)

    print("\nStep 4: Decompose skeleton into segments")
    junction_clusters, segments, endpoints = decompose_skeleton(skeleton)

    print("\nStep 5: Assemble path from segments")
    ordered, junction_seam_indices = build_path_from_segments(junction_clusters, segments, endpoints)

    if len(ordered) < 50:
        print("ERROR: Path too short.")
        sys.exit(1)

    print(f"\nStep 6: Smooth and simplify")
    simplified = smooth_and_simplify(ordered, junction_seam_indices=junction_seam_indices)

    print("\nStep 7: Scale to viewBox")
    scaled, viewbox = scale_to_viewbox(simplified)

    print("\nStep 8: Generate SVG path")
    path_d = points_to_svg_path(scaled)

    print("\n--- SVG Path Data ---")
    print(f'viewBox="{viewbox}"')
    print(f'd="{path_d}"')

    print("\nStep 9: Write verification SVG")
    write_svg(path_d, viewbox, svg_output, image_path)
    print("\nDone.")
    return path_d, viewbox


if __name__ == "__main__":
    main()
