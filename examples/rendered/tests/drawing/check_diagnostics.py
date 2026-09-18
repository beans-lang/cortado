#!/usr/bin/env python3
"""Check that a bad literal SVG path points at its .bx source."""
from pathlib import Path
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[4]
GENERATOR = Path(os.environ.get("CORTADO_BX", str(ROOT / "build/cortado-bx")))

with tempfile.TemporaryDirectory() as scratch:
    for filename, expected in [
        ("bad_path.bx", "bad_path.bx:1:30: error: SVG path command M needs groups of 2 numbers"),
        ("bad_easing.bx", "bad_easing.bx:1:12: error: transition_easing must be linear or ease_in_out"),
        ("bad_box_fill.bx", "bad_box_fill.bx:1:6: error: <Box> has no fill"),
    ]:
        source = ROOT / "examples/rendered/tests/drawing" / filename
        result = subprocess.run([str(GENERATOR), "build", str(source), "-o",
                                 str(Path(scratch) / (filename + ".b"))], cwd=ROOT,
                                text=True, capture_output=True)
        if result.returncode == 0 or expected not in result.stderr:
            raise SystemExit(f"{filename} diagnostic changed:\n{result.stderr}")
    valid = ROOT / "examples/rendered/tests/drawing/good_rectangle_fill.bx"
    result = subprocess.run([str(GENERATOR), "build", str(valid), "-o",
                             str(Path(scratch) / "good_rectangle_fill.b")], cwd=ROOT,
                            text=True, capture_output=True)
    if result.returncode != 0:
        raise SystemExit(f"Rectangle.fill was refused:\n{result.stderr}")
print("ok source-mapped path, easing, and drawing-only fill diagnostics")
