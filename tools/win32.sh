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
source "$root/tools/beans_env.sh"
cortado_beans_env "$BEANSC" || exit 1

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
# `BEANS_BUILD_JOBS=1` is load-bearing, not a speed setting: above about four
# megabytes of IR beansc splits a module into eight parallel chunks, and there
# is then no single `.ll` to pick up. One job puts the chunk count back to one.
rm -f "$root/build/$name".*.ll "$root/build/$name".*_ffi.c
( cd "$root" && BEANS_BUILD_JOBS=1 "$BEANSC" build "tests/$name.b" \
    --target x86_64-pc-windows-gnu -o "$out/$name.unused" ) \
    >"$out/$name.beansc" 2>&1 || true
ir="$(ls -t "$root/build/$name".*.ll 2>/dev/null | head -1 || true)"
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

bridge="$(ls -t "$root/build/$name".*_ffi.c 2>/dev/null | head -1 || true)"
if [[ -n "$bridge" ]]; then
    "$CC" -O1 -c "$bridge" -o "$out/$name.ffi.o"
    objects+=("$out/$name.ffi.o")
fi

# The host itself, with the warnings on. A Win32 header mismatch shows up as a
# warning long before it shows up as a wrong answer.
# One file per concern under src/win32/, compiled from a glob so a file added
# to the host and forgotten here is not silently left out of the link.
#
# Into a directory of their own, because a host file and a test case can share
# a name: `tests/clock.b` and `src/win32/clock.c` both wanted to be `clock.o`,
# the host overwrote the program, and the link failed for `main` and every
# symbol the program defines — a long way from anything that mentioned either
# file.
mkdir -p "$out/host"
for source in "$root"/src/win32/*.c; do
    object="$out/host/$(basename "${source%.c}").o"
    "$CC" -O1 -g -Wall -Wextra -I "$root/src" -I "$root/src/win32" \
          -c "$source" -o "$object"
    objects+=("$object")
done

# The libraries the host needs, read out of `beans.pot` rather than written
# here.
#
# A second copy of that list is a list that drifts, and this one did: adding
# `iphlpapi` to the manifest for `src/win32/machine.c` left this line behind,
# and the failure was an undefined reference at link time from a script nobody
# would think to edit. On a Windows machine `beansc` reads those rows itself;
# this leg links by hand because beansc's bundled clang has no Windows sysroot,
# and reading the same rows is what keeps the two the same.
host_libraries=()
while read -r library; do
    host_libraries+=("-l$library")
done < <(sed -n 's/^link windows library "\(.*\)"$/\1/p' "$root/beans.pot")
if [[ ${#host_libraries[@]} -eq 0 ]]; then
    echo "win32: no 'link windows library' rows in beans.pot — the manifest moved" >&2
    exit 1
fi

# Statically, because mingw's own libwinpthread is a DLL that only exists
# beside a mingw installation. A binary that needs it is not a Windows program
# anybody else can run, and the failure is a silent exit before `main`.
#
# The second row is the Beans runtime's own, which is not in the manifest
# because it belongs to the language rather than to this package.
"$CC" -static "${objects[@]}" -o "$out/$name.exe" \
      "${host_libraries[@]}" \
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
#
# **Two things about the container leg were learned the expensive way, and both
# are load-bearing.**
#
# `xvfb-run` hangs here. It starts the X server, the program runs and exits,
# and the wrapper never returns: `docker ps` showed nine containers, the oldest
# two hours old, each holding a live `xvfb-run` and an `Xvfb` with no Wine
# process left under it. The same executable run against an `Xvfb` started by
# hand finishes in seconds and prints its golden. So the server is started
# here, `DISPLAY` is exported, and the wrapper is not used.
#
# And a display is genuinely needed: with none, `CreateWindowExW` fails and the
# host answers `stale_handle: could not set a surface title`. Running Wine bare
# is not an option, only running it without that wrapper.
#
# `CORTADO_WINE_TIMEOUT` seconds, because a leg that hangs is worse than one
# that fails: a failure names itself and a hang looks exactly like slow. It is
# generous — Wine under amd64 emulation on an Apple Silicon Mac is not fast —
# and the number is a cliff, not a budget.
run_exe() {
    if [[ -n "${CORTADO_WINE:-}" ]]; then
        $CORTADO_WINE "$1"
        return
    fi
    local wine
    wine="$(command -v wine64 || command -v wine || true)"
    if [[ -n "$wine" ]]; then
        if command -v Xvfb >/dev/null 2>&1; then
            Xvfb :99 -screen 0 1280x1024x24 -nolisten tcp >/dev/null 2>&1 &
            local server=$!
            local waited=0
            while [[ ! -e /tmp/.X11-unix/X99 && $waited -lt 40 ]]; do
                sleep 0.25
                waited=$(( waited + 1 ))
            done
            DISPLAY=:99 timeout "$wine_timeout" "$wine" "$1"
            local answer=$?
            kill "$server" 2>/dev/null || true
            return $answer
        fi
        timeout "$wine_timeout" "$wine" "$1"
        return
    fi
    docker run --rm --platform linux/amd64 -v "$out":/w -w /w "$image" \
        bash -lc '
            Xvfb :99 -screen 0 1280x1024x24 -nolisten tcp >/dev/null 2>&1 &
            server=$!
            waited=0
            while [ ! -e /tmp/.X11-unix/X99 ] && [ $waited -lt 40 ]; do
                sleep 0.25
                waited=$(( waited + 1 ))
            done
            DISPLAY=:99 WINEDEBUG=-all timeout '"$wine_timeout"' \
                /usr/lib/wine/wine64 /w/'"$(basename "$1")"'
            answer=$?
            kill $server 2>/dev/null || true
            exit $answer
        '
}

image="${CORTADO_WINE_IMAGE:-cortado-wine}"
wine_timeout="${CORTADO_WINE_TIMEOUT:-300}"
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
# `PIPESTATUS[0]` is Wine's own exit code rather than the pipeline's, which is
# what lets 124 — the timeout — say so by name instead of arriving as one more
# "exited non-zero".
#
# `set +e` around it rather than a trailing `|| true`, and the difference is
# not style: `||` runs a second command, and a simple command *replaces*
# PIPESTATUS with its own status. The `true` would answer for Wine, and every
# failure would read as a pass.
set +e
run_exe "$out/$name.exe" 2>"$out/$name.stderr" | tr -d '\r' >"$out/$name.stdout"
answer=${PIPESTATUS[0]}
set -e
if [[ $answer -eq 124 ]]; then
    echo "FAIL win32 $name: still running after ${wine_timeout}s — raise CORTADO_WINE_TIMEOUT if this machine is really that slow" >&2
    head -10 "$out/$name.stderr" >&2
    exit 1
fi
if [[ $answer -ne 0 ]]; then
    echo "FAIL win32 $name: exited $answer" >&2
    head -10 "$out/$name.stderr" >&2
    exit 1
fi
if ! diff -u "$root/tests/$name.out" "$out/$name.stdout"; then
    echo "FAIL win32 $name: the Win32 host prints something else" >&2
    exit 1
fi
echo "ok win32: tests/$name.out is the same bytes through the Win32 host"
