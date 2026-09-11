#!/usr/bin/env bash
# Holds every host in src/ to src/cortado_host.h.
#
# The header is a contract with as many implementations as cortado has
# platforms, and the C linker is the real enforcement: add an entry point, forget
# one host, and that platform's build fails. But a link only happens where a
# toolchain does — a Mac cannot link a Win32 host, and a machine with no GTK
# cannot link a GTK one — so a missing function would go unnoticed until
# somebody with the right machine tried.
#
# This is that check, done on text so it runs anywhere: every function the
# header declares must be defined by every host present. It does not prove a
# host is correct; it proves none of them is silently incomplete.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$root/build"
header="$root/src/cortado_host.h"

# The name immediately before the opening parenthesis of a declaration. The
# return types are ctd_status, ctd_handle, int32_t, uint32_t and void, so a
# pattern anchored on the type would also match the typedefs.
grep -oE '\b(ctd_[a-z0-9_]+)\(' "$header" \
    | sed 's/($//; s/(//' | sort -u >"$root/build/.host.declared"

hosts=0
for host in "$root"/src/cortado_*.m "$root"/src/cortado_*.c; do
    [[ -e "$host" ]] || continue
    hosts=$((hosts + 1))
    name="$(basename "$host")"
    # A definition is a name before `(` at the start of a line — a call is
    # indented, and a declaration inside the file is followed by `;`.
    grep -oE '^[a-z0-9_ ]*\**(ctd_[a-z0-9_]+)\(' "$host" \
        | grep -oE 'ctd_[a-z0-9_]+' | sort -u >"$root/build/.host.$name"
    missing="$(comm -23 "$root/build/.host.declared" "$root/build/.host.$name" || true)"
    if [[ -n "$missing" ]]; then
        echo "$name does not implement every entry point in cortado_host.h:" >&2
        echo "$missing" | sed 's/^/  /' >&2
        echo >&2
        echo "A host that is missing one is a platform whose build breaks for" >&2
        echo "whoever has that machine, not for whoever added the function." >&2
        exit 1
    fi
done

if [[ $hosts -eq 0 ]]; then
    echo "check_hosts: there are no hosts in src/ — the header describes nothing" >&2
    exit 1
fi

echo "ok hosts: $hosts implementing all $(wc -l <"$root/build/.host.declared" | tr -d ' ') entry points"
