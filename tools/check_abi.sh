#!/usr/bin/env bash
# Holds the three halves of cortado's platform boundary to each other.
#
# 1. Every function in src/cortado_host.h is bound in host/sys.b. A host entry
#    point nothing can call is dead weight; one that was added and never
#    regenerated is worse, because the binding silently lacks it.
# 2. No Beans file outside cortado.host names a platform symbol. This is the
#    structural form of cortado's central rule — Objective-C, COM and GObject
#    stop at the C boundary — and it is a gate rather than a comment because a
#    comment cannot fail.
# 3. Every bound symbol is either reached by the test suite or listed in
#    SKIPPED.md with a reason.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
header="$root/src/cortado_host.h"
generated="$root/host/sys.b"
mkdir -p "$root/build"
status=0

# ---- 1. the header and the binding agree ----
# The name immediately before an open paren, so the `ctd_status` return type
# on the same line is not mistaken for a second entry point.
grep -vE '^typedef' "$header" \
    | grep -oE 'ctd_[a-z_0-9]+\(' | tr -d '(' | sort -u >"$root/build/.abi.header"
grep -oE 'extern "C" fn (ctd_[a-z_0-9]+)' "$generated" \
    | grep -oE 'ctd_[a-z_0-9]+' | sort -u >"$root/build/.abi.bound"

if ! diff -u "$root/build/.abi.header" "$root/build/.abi.bound" >"$root/build/.abi.diff"; then
    echo "host/sys.b is out of date — run tools/regen_sys.sh:" >&2
    echo "  < declared in the header      > bound in Beans" >&2
    cat "$root/build/.abi.diff" >&2
    status=1
fi

# ---- 2. platform names never leak out of cortado.host ----
# Comments are stripped first: a doc comment explaining that a Button is an
# NSButton on macOS is the documentation working, not a leak.
leaked=""
while IFS= read -r file; do
    if sed 's://.*::' "$file" \
        | grep -qE 'objc_|msgSend|sel_registerName|NSString|NSView|NSWindow|HWND|LPCWSTR|g_object_|GtkWidget|UIView'; then
        leaked="$leaked$file"$'\n'
    fi
done < <(find "$root" -name '*.b' -not -path "$root/host/*" -not -path "$root/build/*")
if [[ -n "$leaked" ]]; then
    echo "platform symbols reached Beans outside cortado.host:" >&2
    echo "$leaked" >&2
    echo "Everything platform-specific belongs in src/, behind the flat C ABI." >&2
    status=1
fi

# ---- 3. every bound symbol is exercised or excused ----
: >"$root/build/.abi.unused"
while read -r symbol; do
    if grep -rq "$symbol" --include='*.b' "$root/host" "$root/widgets" "$root/surface" \
        "$root/events" "$root/platform" 2>/dev/null \
        && [[ $(grep -rl "$symbol" --include='*.b' "$root" | grep -vc "sys\.b$") -gt 0 ]]; then
        continue
    fi
    if grep -q "^$symbol\b" "$root/SKIPPED.md" 2>/dev/null; then
        continue
    fi
    echo "$symbol" >>"$root/build/.abi.unused"
done <"$root/build/.abi.bound"

if [[ -s "$root/build/.abi.unused" ]]; then
    echo "bound but never called, and not listed in SKIPPED.md:" >&2
    sed 's/^/  /' "$root/build/.abi.unused" >&2
    echo "Either wrap it, or write down why it is not wrapped yet." >&2
    status=1
fi

if [[ $status -eq 0 ]]; then
    echo "ok abi: $(wc -l <"$root/build/.abi.bound" | tr -d ' ') entry points bound, wrapped and contained"
fi
exit $status
