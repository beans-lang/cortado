#!/usr/bin/env bash
# Renders cortado's controls onto the reference boards and compares them.
#
# The plan comes from the capture, so both sides draw the same boards at the
# same scale. Stale cortado PNGs are removed first: a file left from an earlier
# build would be compared as if this build had drawn it.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
scale="${1:-2}"
ref="${REFERENCE:-build/reference}"
out="${COMPARE:-build/compare}"
mkdir -p "$out"
rm -rf "$out/cortado"
mkdir -p "$out/cortado"
python3 tools/reference/plan.py "$ref" "$out/plan.tsv" "$scale"
./build/reference-shots "$out/plan.tsv" "$out/cortado"
python3 tools/reference/compare.py "$ref" "$out/cortado" "$out"
