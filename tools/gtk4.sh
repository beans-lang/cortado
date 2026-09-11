#!/usr/bin/env bash
# Builds and runs a cortado test against the **GTK4** host.
#
# GTK4 has a macOS backend, so the Linux host can be compiled and run on this
# machine — which is the only reason a third implementation of the ABI could be
# checked at all before anyone puts cortado on a Linux box. What it proves is
# what it can prove: that the host in `src/gtk4/` implements the contract, and
# that `tests/roles.out` is the same bytes through it. What it cannot prove is
# anything about X11 or Wayland, which are not here.
#
# beansc picks a host from the manifest by target OS, and on macOS that is the
# AppKit one — so this asks beansc for the IR and links the GTK4 host beside it
# by hand, the same shape `tools/sanitize.sh` uses.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="$root/build/gtk4"
mkdir -p "$out"

BEANSC="${BEANSC:-}"
if [[ -z "$BEANSC" ]]; then
    if [[ -x "$root/../../beans/build/beansc" ]]; then
        BEANSC="$root/../../beans/build/beansc"
    else
        BEANSC="$(command -v beansc)"
    fi
fi
beans_tree="$(cd "$(dirname "$BEANSC")/.." && pwd)"
export BEANS_RUNTIME="$beans_tree/runtime/beans_rt.c"
export BEANS_STDLIB="$beans_tree/stdlib/std"
export BEANS_ENCODING="$beans_tree/runtime/encoding"
export BEANS_NET="$beans_tree/runtime/net"
export BEANS_LOG="$beans_tree/runtime/log"

if ! pkg-config --exists gtk4 2>/dev/null; then
    echo "SKIP gtk4: no gtk4 on pkg-config's path"
    exit 0
fi

name="${1:-roles}"
source="$root/tests/$name.b"
[[ -f "$source" ]] || { echo "gtk4: no tests/$name.b" >&2; exit 1; }

# The host is one file per concern under src/gtk4/. A glob rather than a list:
# a file added to the host and forgotten here would simply not be linked, and
# the failure would be an undefined symbol a long way from its cause.
host_objects=()
for source in "$root"/src/gtk4/*.c; do
    object="$out/$(basename "${source%.c}").o"
    clang -c -O1 -g -Wall -Wextra $(pkg-config --cflags gtk4) \
          -I "$root/src" -I "$root/src/gtk4" "$source" -o "$object"
    host_objects+=("$object")
done
if [[ ${#host_objects[@]} -eq 0 ]]; then
    echo "gtk4: no host sources in src/gtk4 — the layout moved" >&2
    exit 1
fi

# `BEANS_BUILD_JOBS=1` is load-bearing, not a speed setting: above about four
# megabytes of IR beansc splits a module into eight parallel chunks, and there
# is then no single `.ll` to pick up. One job puts the chunk count back to one.
rm -f "$root/build/$name".*.ll "$root/build/$name".*_ffi.c
( cd "$root" && BEANS_BUILD_JOBS=1 "$BEANSC" build "tests/$name.b" -o "$out/$name.unused" >/dev/null )
ir="$(ls -t "$root/build/$name".*.ll 2>/dev/null | head -1 || true)"
[[ -n "$ir" ]] || { echo "gtk4: beansc emitted no IR for $name" >&2; exit 1; }
ffi=()
bridge="$(ls -t "$root/build/$name".*_ffi.c 2>/dev/null | head -1 || true)"
[[ -n "$bridge" ]] && ffi+=("$bridge")

clang -O1 -g -pthread -Wno-override-module \
      "$ir" "$BEANS_RUNTIME" "${host_objects[@]}" "${ffi[@]}" \
      $(pkg-config --libs gtk4) -lm -o "$out/$name"

"$out/$name" >"$out/$name.stdout" 2>"$out/$name.stderr" || {
    echo "FAIL gtk4 $name: exited non-zero" >&2
    head -10 "$out/$name.stderr" >&2
    exit 1
}

if ! diff -u "$root/tests/$name.out" "$out/$name.stdout"; then
    echo "FAIL gtk4 $name: the GTK4 host prints something else" >&2
    exit 1
fi
echo "ok gtk4: tests/$name.out is the same bytes through the GTK4 host"
