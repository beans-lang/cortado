#!/usr/bin/env bash
# Regenerates host/sys.b from src/cortado_host.h.
#
# Run this after any change to the header, then run tools/check_abi.sh and
# tools/check_constants.sh. The generated file is committed so a consumer of
# cortado adds one `require` row and needs no code generator.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BEANSC="${BEANSC:-${BEANS_ROOT:-$root/../../beans}/build/beansc}"

"$BEANSC" bindgen "$root/src/cortado_host.h" \
    -o "$root/host/sys.b" --package host --pub

echo "wrote host/sys.b"
"$root/tools/check_abi.sh"
"$root/tools/check_constants.sh"
