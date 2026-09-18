#!/usr/bin/env python3
"""Compares the dominant fill of each control region, native against cortado.

A fill that is off by a step is invisible in a thumbnail and obvious here, and
it is the first thing to fix: geometry read over the wrong colour is noise.
"""
import json, os, sys
from collections import Counter
import numpy as np
from PIL import Image

root = sys.argv[1] if len(sys.argv) > 1 else "build/reference"
mine = sys.argv[2] if len(sys.argv) > 2 else "build/compare/cortado"
pick = sys.argv[3] if len(sys.argv) > 3 else ""


def dominant(path, shot):
    img = np.asarray(Image.open(path).convert("RGBA")).astype(np.uint8)
    s = shot["scale"]
    x0 = int(round(shot["pad"] * s)); y0 = int(round(shot["pad"] * s))
    x1 = x0 + int(round(shot["controlWidth"] * s)); y1 = y0 + int(round(shot["controlHeight"] * s))
    patch = img[y0:y1, x0:x1].reshape(-1, 4)
    if patch.size == 0:
        return "none"
    return "%02x%02x%02x%02x" % Counter(map(tuple, patch)).most_common(1)[0][0]


shots = json.load(open(os.path.join(root, "shots.json")))["shots"]
seen = set()
for shot in shots:
    if shot["scale"] != 2:
        continue
    if pick and pick not in shot["control"]:
        continue
    a = os.path.join(root, "shots", shot["file"])
    b = os.path.join(mine, shot["file"])
    if not (os.path.exists(a) and os.path.exists(b)):
        continue
    key = (shot["control"], shot["size"], shot["state"], shot["appearance"])
    if key in seen:
        continue
    seen.add(key)
    na, nb = dominant(a, shot), dominant(b, shot)
    if na == nb:
        continue
    print(f"{shot['control']:17s} {shot['size']:7s} {shot['state']:15s} {shot['appearance']:5s} "
          f"native={na} cortado={nb}")
