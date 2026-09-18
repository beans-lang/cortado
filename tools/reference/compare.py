#!/usr/bin/env python3
"""Holds cortado's controls against the pinned AppKit reference, pixel for pixel.

For every shot in the plan it writes, into <out>/:
  native/<file>      the AppKit capture
  cortado/<file>     cortado's own render of the same board
  side/<file>        the two beside each other
  overlay/<file>     cortado over native at 50%
  diff/<file>        the per-pixel difference, amplified
and a report with the geometry and typography comparison per control.

Regions are compared inside the control's own frame, never over the whole
board: a matching background must not be able to hide a wrong border.
"""
import json, os, sys
import numpy as np
from PIL import Image

root = sys.argv[1] if len(sys.argv) > 1 else "build/reference"
mine = sys.argv[2] if len(sys.argv) > 2 else "build/compare/cortado"
out = sys.argv[3] if len(sys.argv) > 3 else "build/compare"
for name in ("side", "overlay", "diff"):
    os.makedirs(os.path.join(out, name), exist_ok=True)

shots = json.load(open(os.path.join(root, "shots.json")))["shots"]


def load(path):
    return np.asarray(Image.open(path).convert("RGBA")).astype(np.int16)


def save(array, path):
    Image.fromarray(np.clip(array, 0, 255).astype(np.uint8), "RGBA").save(path)


def painted_box(img, tol=2):
    page = img[1, 1]
    mask = np.abs(img - page).max(axis=2) > tol
    if not mask.any():
        return None
    ys, xs = np.where(mask)
    return int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())


rows = []
for shot in shots:
    a_path = os.path.join(root, "shots", shot["file"])
    b_path = os.path.join(mine, shot["file"])
    if not os.path.exists(a_path) or not os.path.exists(b_path):
        continue
    native, ours = load(a_path), load(b_path)
    if native.shape != ours.shape:
        rows.append({**{k: shot[k] for k in ("file", "control", "size", "state", "appearance", "scale")},
                     "status": "size-mismatch",
                     "nativeShape": list(native.shape), "cortadoShape": list(ours.shape)})
        continue
    scale = shot["scale"]
    pad = int(round(shot["pad"] * scale))
    w = int(round(shot["controlWidth"] * scale))
    h = int(round(shot["controlHeight"] * scale))
    # The control's own frame, grown by the focus ring's reach.
    ring = int(round(4 * scale))
    x0, y0 = max(pad - ring, 0), max(pad - ring, 0)
    x1, y1 = min(pad + w + ring, native.shape[1]), min(pad + h + ring, native.shape[0])
    region_n = native[y0:y1, x0:x1]
    region_o = ours[y0:y1, x0:x1]
    delta = np.abs(region_n.astype(np.int32) - region_o.astype(np.int32))[..., :3]
    worst = int(delta.max()) if delta.size else 0
    wrong = int((delta.max(axis=2) > 2).sum())
    total = int(delta.shape[0] * delta.shape[1]) or 1

    side = np.zeros((native.shape[0], native.shape[1] * 2 + 8, 4), dtype=np.int16)
    side[..., 3] = 255
    side[:, :native.shape[1]] = native
    side[:, native.shape[1] + 8:] = ours
    save(side, os.path.join(out, "side", shot["file"]))

    blend = (native.astype(np.float32) * 0.5 + ours.astype(np.float32) * 0.5)
    blend[..., 3] = 255
    save(blend, os.path.join(out, "overlay", shot["file"]))

    amplified = np.zeros_like(native)
    full = np.abs(native.astype(np.int32) - ours.astype(np.int32))[..., :3]
    amplified[..., 0] = np.clip(full.max(axis=2) * 6, 0, 255)
    amplified[..., 1] = np.clip(full.max(axis=2) * 2, 0, 255)
    amplified[..., 3] = 255
    save(amplified, os.path.join(out, "diff", shot["file"]))

    box_n = painted_box(native)
    box_o = painted_box(ours)

    def frame(box):
        if box is None:
            return None
        return {"x": round((box[0] / scale) - shot["pad"], 3),
                "y": round((box[1] / scale) - shot["pad"], 3),
                "w": round((box[2] - box[0] + 1) / scale, 3),
                "h": round((box[3] - box[1] + 1) / scale, 3)}

    rows.append({
        **{k: shot[k] for k in ("file", "control", "size", "state", "appearance", "scale")},
        "status": "compared",
        "worstChannel": worst,
        "wrongPixels": wrong,
        "regionPixels": total,
        "wrongShare": round(wrong / total, 5),
        "nativeFrame": frame(box_n),
        "cortadoFrame": frame(box_o),
    })

report = {"root": root, "cortado": mine, "rows": rows}
json.dump(report, open(os.path.join(out, "report.json"), "w"), indent=1)
compared = [r for r in rows if r["status"] == "compared"]
exact = [r for r in compared if r["wrongPixels"] == 0]
print(f"compared {len(compared)} shot(s); {len(exact)} exact, {len(compared) - len(exact)} differ")
worst = sorted(compared, key=lambda r: -r["wrongShare"])[:15]
for r in worst:
    n, c = r["nativeFrame"], r["cortadoFrame"]
    ns = f"{n['x']},{n['y']} {n['w']}x{n['h']}" if n else "none"
    cs = f"{c['x']},{c['y']} {c['w']}x{c['h']}" if c else "none"
    print(f"  {r['control']:17s} {r['size']:7s} {r['state']:15s} {r['appearance']:5s} @{int(r['scale'])}x "
          f"wrong={r['wrongShare']*100:6.2f}%  max={r['worstChannel']:3d}  native[{ns}] cortado[{cs}]")
bad = [r for r in rows if r["status"] != "compared"]
if bad:
    print(f"{len(bad)} shot(s) could not be compared; first: {bad[0]['file']} ({bad[0]['status']})")
