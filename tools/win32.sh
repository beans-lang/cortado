#!/usr/bin/env bash
# Builds — and where there is something to run it with, runs — a cortado test
# against the **Win32** host.
#
# Windows is the one target in cortado's set that this machine cannot build
# the ordinary way. `beansc build --target x86_64-pc-windows-gnu` emits correct
# IR and then hands the C half to its bundled clang, which has no Windows
# sysroot and stops at `#include <errno.h>`. So the two halves are done
# separately, which is the same shape `tools/gtk4.sh` and `tools/sanitize.sh`
# already use:
#
#   * the Beans half through `llc`, which turns beansc's own IR into a COFF
#     object for the Windows triple;
#   * the C half — the runtime, the FFI bridge and the host — through
#     mingw-w64, which has the headers and the import libraries.
#
# The result is a real PE32+ executable. On a Windows machine none of this is
# needed: `beans.pot` already carries the `csrc windows` and `link windows`
# rows, and `beansc build` does the whole thing.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="$root/build/win32"
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

CC="${CORTADO_MINGW:-x86_64-w64-mingw32-gcc}"
command -v "$CC" >/dev/null 2>&1 || {
    echo "SKIP win32: no $CC — 'brew install mingw-w64'"
    exit 0
}
LLC="${CORTADO_LLC:-}"
if [[ -z "$LLC" ]]; then
    for candidate in /opt/homebrew/opt/llvm/bin/llc /usr/local/opt/llvm/bin/llc llc; do
        if command -v "$candidate" >/dev/null 2>&1; then LLC="$candidate"; break; fi
    done
fi
[[ -n "$LLC" ]] || { echo "SKIP win32: no llc — 'brew install llvm'"; exit 0; }

name="${1:-roles}"
source="$root/tests/$name.b"
[[ -f "$source" ]] || { echo "win32: no tests/$name.b" >&2; exit 1; }

# beansc stops at the C step for this target, and that is expected here: what
# is wanted is the IR it has already written. A failure that is *not* the
# sysroot would be hidden by ignoring the exit code, so the log is kept and
# shown if no IR turns up.
rm -f "$root/build/$name".*.ll "$root/build/$name".*_ffi.c
( cd "$root" && "$BEANSC" build "tests/$name.b" \
    --target x86_64-pc-windows-gnu -o "$out/$name.unused" ) \
    >"$out/$name.beansc" 2>&1 || true
ir="$(ls -t "$root/build/$name".*.ll 2>/dev/null | head -1)"
if [[ -z "$ir" ]]; then
    echo "FAIL win32 $name: beansc emitted no Windows IR" >&2
    tail -20 "$out/$name.beansc" >&2
    exit 1
fi
grep -q 'target triple = "x86_64-pc-windows-gnu"' "$ir" || {
    echo "FAIL win32 $name: $ir is not Windows IR" >&2
    exit 1
}

"$LLC" -mtriple=x86_64-pc-windows-gnu -filetype=obj -O2 "$ir" -o "$out/$name.o"

objects=("$out/$name.o")
"$CC" -O1 -c "$BEANS_RUNTIME" -o "$out/beans_rt.o"
objects+=("$out/beans_rt.o")

bridge="$(ls -t "$root/build/$name".*_ffi.c 2>/dev/null | head -1)"
if [[ -n "$bridge" ]]; then
    "$CC" -O1 -c "$bridge" -o "$out/$name.ffi.o"
    objects+=("$out/$name.ffi.o")
fi

# The host itself, with the warnings on. A Win32 header mismatch shows up as a
# warning long before it shows up as a wrong answer.
# One file per concern under src/win32/, compiled from a glob so a file added
# to the host and forgotten here is not silently left out of the link.
for source in "$root"/src/win32/*.c; do
    object="$out/$(basename "${source%.c}").o"
    "$CC" -O1 -g -Wall -Wextra -I "$root/src" -I "$root/src/win32" \
          -c "$source" -o "$object"
    objects+=("$object")
done

# Statically, because mingw's own libwinpthread is a DLL that only exists
# beside a mingw installation. A binary that needs it is not a Windows program
# anybody else can run, and the failure is a silent exit before `main`.
"$CC" -static "${objects[@]}" -o "$out/$name.exe" \
      -lcomctl32 -lcomdlg32 -lgdi32 -luser32 -ladvapi32 \
      -lws2_32 -lmswsock -lbcrypt -luserenv -lntdll -lsynchronization -lm

# Common controls v6 is what makes a button a themed button rather than a flat
# grey rectangle from 1995, and the only way to ask for it without a resource
# compiler is a manifest beside the executable. `csrc` cannot compile a `.rc`,
# so this is the supported alternative and not a workaround.
cat >"$out/$name.exe.manifest" <<'MANIFEST'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0">
  <dependency>
    <dependentAssembly>
      <assemblyIdentity type="win32" name="Microsoft.Windows.Common-Controls"
                        version="6.0.0.0" processorArchitecture="amd64"
                        publicKeyToken="6595b64144ccf1df" language="*" />
    </dependentAssembly>
  </dependency>
</assembly>
MANIFEST

echo "ok win32: tests/$name.b links a PE32+ executable against the Win32 host"

# Running it needs Windows, or something that pretends to be one. Three ways,
# in the order of how much they cost:
#
#   1. CORTADO_WINE, a command that takes the executable's path;
#   2. a wine on PATH — which is what a Linux runner has;
#   3. Docker, running Ubuntu's wine in an amd64 container from
#      `tools/winebox.Dockerfile`. The image is built once and cached.
#
# When none of them is here the leg says so and names what is missing. A
# golden that was never printed proves nothing, and a port nobody has run is
# not a port.
run_exe() {
    if [[ -n "${CORTADO_WINE:-}" ]]; then
        $CORTADO_WINE "$1"
        return
    fi
    local wine
    wine="$(command -v wine64 || command -v wine || true)"
    if [[ -n "$wine" ]]; then
        if command -v xvfb-run >/dev/null 2>&1; then
            xvfb-run -a "$wine" "$1"
        else
            "$wine" "$1"
        fi
        return
    fi
    docker run --rm --platform linux/amd64 -v "$out":/w -w /w "$image" \
        bash -lc "xvfb-run -a /usr/lib/wine/wine64 /w/$(basename "$1")"
}

image="${CORTADO_WINE_IMAGE:-cortado-wine}"
if [[ -z "${CORTADO_WINE:-}" ]] && ! command -v wine64 >/dev/null 2>&1 \
        && ! command -v wine >/dev/null 2>&1; then
    if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
        echo "SKIP win32_run: nothing here can run a PE — a wine on PATH, a running Docker, or CORTADO_WINE"
        exit 0
    fi
    if ! docker image inspect "$image" >/dev/null 2>&1; then
        docker build --platform linux/amd64 -t "$image" \
            -f "$root/tools/winebox.Dockerfile" "$root/tools" >"$out/winebox.log" 2>&1 || {
            echo "FAIL win32: could not build the wine image" >&2
            tail -20 "$out/winebox.log" >&2
            exit 1
        }
    fi
fi

# Wine writes its own diagnostics to stderr and the X server writes its
# shutdown to the same place, so only stdout is the answer.
run_exe "$out/$name.exe" 2>"$out/$name.stderr" | tr -d '\r' >"$out/$name.stdout" || {
    echo "FAIL win32 $name: exited non-zero" >&2
    head -10 "$out/$name.stderr" >&2
    exit 1
}
if ! diff -u "$root/tests/$name.out" "$out/$name.stdout"; then
    echo "FAIL win32 $name: the Win32 host prints something else" >&2
    exit 1
fi
echo "ok win32: tests/$name.out is the same bytes through the Win32 host"
