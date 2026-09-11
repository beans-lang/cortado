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
#
# **A host is a platform, not a file.** It is either one translation unit,
# `src/cortado_<platform>.{m,c}`, or a directory of them, `src/<platform>/`, and
# the check is against the union of what that platform defines. The earlier
# version of this script globbed files and demanded that *each* file implement
# every entry point, which was true only while a host was a single file — the
# moment `src/mac/` was split by concern it failed with thirty-four missing
# symbols, every one of them present in a sibling file.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$root/build"
header="$root/src/cortado_host.h"

# The name immediately before the opening parenthesis of a declaration. The
# return types are ctd_status, ctd_handle, int32_t, uint32_t and void, so a
# pattern anchored on the type would also match the typedefs.
grep -oE '\b(ctd_[a-z0-9_]+)\(' "$header" \
    | sed 's/($//; s/(//' | sort -u >"$root/build/.host.declared"

# A definition is a name before `(` at the start of a line — a call is
# indented, and a declaration inside the file is followed by `;`.
definitions() {
    cat "$@" 2>/dev/null \
        | grep -oE '^[a-z0-9_ ]*\**(ctd_[a-z0-9_]+)\(' \
        | grep -oE 'ctd_[a-z0-9_]+' | sort -u
}

check() {
    local name="$1"; shift
    definitions "$@" >"$root/build/.host.$name"
    local missing
    missing="$(comm -23 "$root/build/.host.declared" "$root/build/.host.$name" || true)"
    if [[ -n "$missing" ]]; then
        echo "the $name host does not implement every entry point in cortado_host.h:" >&2
        echo "$missing" | sed 's/^/  /' >&2
        echo >&2
        echo "A host that is missing one is a platform whose build breaks for" >&2
        echo "whoever has that machine, not for whoever added the function." >&2
        exit 1
    fi
}

hosts=0
files=0

# A host that is a directory of files, one per concern.
for directory in "$root"/src/*/; do
    [[ -d "$directory" ]] || continue
    name="$(basename "$directory")"
    sources=("$directory"*.m "$directory"*.c)
    present=()
    for source in "${sources[@]}"; do [[ -e "$source" ]] && present+=("$source"); done
    if [[ ${#present[@]} -eq 0 ]]; then
        echo "check_hosts: src/$name/ holds no .m or .c — a host directory with" >&2
        echo "no host in it reads as a platform that passed, so it fails instead." >&2
        exit 1
    fi
    check "$name" "${present[@]}"
    hosts=$((hosts + 1))
    files=$((files + ${#present[@]}))
done

# A host that is still a single translation unit.
for source in "$root"/src/cortado_*.m "$root"/src/cortado_*.c; do
    [[ -e "$source" ]] || continue
    check "$(basename "$source")" "$source"
    hosts=$((hosts + 1))
    files=$((files + 1))
done

if [[ $hosts -eq 0 ]]; then
    echo "check_hosts: there are no hosts in src/ — the header describes nothing" >&2
    exit 1
fi

echo "ok hosts: $hosts implementing all $(wc -l <"$root/build/.host.declared" | tr -d ' ') entry points, across $files files"
