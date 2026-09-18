#!/usr/bin/env python3
"""Turns the reference shots into numbers: bounds, corner radii, fills, borders.

Reads <root>/shots.json and the PNGs beside it; writes <root>/measured.json and
prints a table. Every number is read off a capture; none is guessed. Corner radii
come from the 4x shots, which resolve a half-point.
"""
import json, os, sys, math
from collections import Counter
import numpy as np
from PIL import Image

root = sys.argv[1] if len(sys.argv) > 1 else "build/reference"
only = sys.argv[2] if len(sys.argv) > 2 else None


def load(path):
    return np.asarray(Image.open(path).convert("RGBA")).astype(np.float64)


def hexof(px):
    return "%02x%02x%02x%02x" % tuple(int(round(v)) for v in px[:4])


def bounds(diff, tol=2.0):
    mask = diff > tol
    if not mask.any():
        return None
    ys, xs = np.where(mask)
    return int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())


def dominant(img, box, scale):
    """The most common opaque colour inside the shape, ignoring a 1pt rim."""
    x0, y0, x1, y1 = box
    inset = max(int(round(1.5 * scale)), 1)
    patch = img[y0 + inset:y1 - inset + 1, x0 + inset:x1 - inset + 1]
    if patch.size == 0:
        patch = img[y0:y1 + 1, x0:x1 + 1]
    flat = patch.reshape(-1, 4)
    counts = Counter(tuple(int(round(v)) for v in row) for row in flat)
    return np.array(counts.most_common(1)[0][0], dtype=np.float64)


def corner_inset(cov, box, corner):
    """Coverage-50% inset per row, walking in from one corner."""
    x0, y0, x1, y1 = box
    rows = []
    height = y1 - y0 + 1
    width = x1 - x0 + 1
    for step in range(0, min(height // 2 + 1, 40)):
        y = y0 + step if corner in ("tl", "tr") else y1 - step
        line = cov[y, x0:x1 + 1]
        hit = np.where(line >= 0.5)[0]
        if hit.size == 0:
            rows.append(None)
            continue
        rows.append(int(hit.min()) if corner in ("tl", "bl") else int(width - 1 - hit.max()))
    return rows


def fit_radius(rows, scale):
    """Least-squares circular radius over the corner profile, in points."""
    best = (0.0, float("inf"))
    for tenth in range(0, 400):
        r = tenth / 10.0 / 1.0
        rp = r * scale
        if rp < 1:
            continue
        err, n = 0.0, 0
        for dy, inset in enumerate(rows):
            if inset is None or dy > rp:
                continue
            predicted = rp - math.sqrt(max(rp * rp - (rp - dy) ** 2, 0.0))
            err += (predicted - inset) ** 2
            n += 1
        if n >= 3:
            score = err / n
            if score < best[1]:
                best = (r, score)
    return best


def border_run(img, box, scale, fill):
    """Colours going down from the top edge at the horizontal centre."""
    x0, y0, x1, y1 = box
    cx = (x0 + x1) // 2
    depth = min(int(round(4 * scale)), max((y1 - y0) // 2, 1))
    run = [hexof(img[y0 + i, cx]) for i in range(depth)]
    thickness = 0
    for i in range(depth):
        if np.abs(img[y0 + i, cx] - fill).max() <= 3:
            break
        thickness += 1
    return run, thickness / scale


shots = json.load(open(os.path.join(root, "shots.json")))["shots"]
rows = []
for shot in shots:
    if only and only not in shot["file"]:
        continue
    path = os.path.join(root, "shots", shot["file"])
    if not os.path.exists(path):
        continue
    img = load(path)
    scale = shot["scale"]
    page = img[1, 1].copy()
    diff = np.abs(img - page).max(axis=2)
    box = bounds(diff)
    entry = {k: shot[k] for k in ("file", "control", "size", "state", "appearance", "scale",
                                  "controlWidth", "controlHeight", "pad")}
    entry["page"] = hexof(page)
    if box is None:
        entry["painted"] = None
        rows.append(entry)
        continue
    x0, y0, x1, y1 = box
    entry["painted"] = {
        "x": round((x0 / scale) - shot["pad"], 3), "y": round((y0 / scale) - shot["pad"], 3),
        "w": round((x1 - x0 + 1) / scale, 3), "h": round((y1 - y0 + 1) / scale, 3),
    }
    fill = dominant(img, box, scale)
    entry["fill"] = hexof(fill)
    span = max(np.abs(fill - page).max(), 1.0)
    cov = np.clip(diff / span, 0, 1)
    if scale >= 4:
        radii = {}
        for corner in ("tl", "tr", "bl", "br"):
            r, mse = fit_radius(corner_inset(cov, box, corner), scale)
            radii[corner] = round(r, 2)
            radii[corner + "Mse"] = round(mse, 3)
        entry["radii"] = radii
    run, thickness = border_run(img, box, scale, fill)
    entry["topRun"] = run
    entry["borderThickness"] = round(thickness, 3)
    rows.append(entry)

out = os.path.join(root, "measured.json")
json.dump({"measured": rows}, open(out, "w"), indent=1)
print("wrote", out, len(rows), "rows")
