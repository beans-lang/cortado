#!/usr/bin/env python3
"""Typed table data must fail at the .bx attribute that supplied a string."""
from pathlib import Path
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[4]
GENERATOR = Path(os.environ.get("CORTADO_BX", str(ROOT / "build/cortado-bx")))

with tempfile.TemporaryDirectory() as scratch:
    for filename, message in [
        ("bad_table_columns.bx", "Table columns takes a List<string> expression"),
        ("bad_table_widths.bx", "column_widths takes a typed expression"),
        ("bad_table_source.bx", "Table source takes a TableRows expression"),
        ("bad_table_editable_when.bx", "Table editable_when takes a TableEditRule expression"),
    ]:
        source = Path(__file__).with_name(filename)
        result = subprocess.run([str(GENERATOR), "build", str(source), "-o",
                                 str(Path(scratch) / (filename + ".b"))], cwd=ROOT,
                                text=True, capture_output=True)
        if result.returncode == 0 or f"{filename}:1:" not in result.stderr or message not in result.stderr:
            raise SystemExit(f"{filename} diagnostic changed:\n{result.stderr}")
print("ok source-mapped typed table diagnostics")
