#!/usr/bin/env python3
"""The compiler reports a malformed accessible name at its .bx source."""
from pathlib import Path
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[4]
GENERATOR = Path(os.environ.get("CORTADO_BX", str(ROOT / "build/cortado-bx")))
SOURCE = ROOT / "examples/rendered/tests/accessibility/bad_label.bx"
with tempfile.TemporaryDirectory() as scratch:
    result = subprocess.run([str(GENERATOR), "build", str(SOURCE), "-o",
                             str(Path(scratch) / "bad_label.b")], cwd=ROOT,
                            text=True, capture_output=True)
    expected = "bad_label.bx:1:12: error: a11y_label is not a true/false attribute"
    if result.returncode == 0 or expected not in result.stderr:
        raise SystemExit(f"a11y_label source diagnostic changed:\n{result.stderr}")
print("ok source-mapped a11y_label diagnostic")
