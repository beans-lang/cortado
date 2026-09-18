#!/usr/bin/env python3
"""Turns the capture's shots.json into the TSV the cortado renderer reads.

Both sides then draw the same boards at the same scale from one list, which is
the only way a difference can be blamed on the drawing rather than the setup.
"""
import json, sys
root = sys.argv[1] if len(sys.argv) > 1 else "build/reference"
out = sys.argv[2] if len(sys.argv) > 2 else "build/compare/plan.tsv"
only_scale = float(sys.argv[3]) if len(sys.argv) > 3 else None
shots = json.load(open(f"{root}/shots.json"))["shots"]
lines = []
for s in shots:
    if only_scale is not None and s["scale"] != only_scale:
        continue
    lines.append("\t".join(str(s[k]) for k in (
        "control", "size", "state", "appearance", "scale", "pad",
        "controlWidth", "controlHeight", "boardWidth", "boardHeight", "file")))
open(out, "w").write("\n".join(lines) + "\n")
print(f"wrote {out} with {len(lines)} shot(s)")
