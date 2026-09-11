#!/usr/bin/env bash
# Holds host/constants.b to src/cortado_host.h.
#
# `beansc bindgen` reads declarations, not the preprocessor, so every `#define`
# in the header has to be hand-copied into Beans. Hand-copied numbers drift,
# and a drifted one is silent: a widget kind off by one builds the wrong
# control, and nothing anywhere says so. This reads both files and compares
# every pair.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
header="$root/src/cortado_host.h"
beans="$root/host/constants.b"

# CTD_W_BUTTON in C is W_BUTTON in Beans: one prefix, dropped.
awk '/^#define CTD_[A-Z0-9_]+ +-?[0-9]+/ { name = substr($2, 5); print name, $3 }' \
    "$header" | sed 's/u$//' | sort >"$root/build/.constants.c"

awk '/^pub const [A-Z0-9_]+: int = -?[0-9]+$/ { name = $3; sub(/:$/, "", name); print name, $6 }' \
    "$beans" | sort >"$root/build/.constants.beans"

if ! diff -u "$root/build/.constants.c" "$root/build/.constants.beans" >"$root/build/.constants.diff"; then
    echo "host/constants.b has drifted from src/cortado_host.h:" >&2
    echo "  < the header      > host/constants.b" >&2
    cat "$root/build/.constants.diff" >&2
    exit 1
fi

echo "ok constants: $(wc -l <"$root/build/.constants.c" | tr -d ' ') values match the header"
