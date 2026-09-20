#!/usr/bin/env bash
# Runs cortado's headless suite under AddressSanitizer and UndefinedBehaviorSanitizer.
#
# `BEANS_SANITIZE` instruments the Beans half, and that is the half a
# sanitizer usually finds nothing in — the compiler's own gate covers it. The
# half worth checking here is `src/mac/`: two thousand lines of Objective-C
# with manual retain and release, a handle table indexed by arithmetic, and a
# string boundary that copies bytes both ways. `csrc` does not pass sanitizer
# flags to a manifest's C sources, so this script compiles the host itself with
# them and links by hand.
#
# Leak detection is off. LeakSanitizer is not supported on Apple silicon, and
# AppKit interns a great deal that it never frees by design; the leak that
# matters here — a widget the handle table forgets — is what
# `tests/events.out`'s registration count checks instead.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="$root/build/sanitize"
rm -rf "$out"
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

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "SKIP sanitize: the only host written is macOS"
    exit 0
fi

# The display stays awake for as long as this script runs.
#
# Not a convenience: a sleeping screen has no active display, so
# CVDisplayLinkCreateWithActiveCGDisplays refuses and every case that drives a
# frame clock fails — `clock`, `frames` and `shader` — in a way that reads
# exactly like a bug in the clock. `test.sh` has held the display awake since
# it was written and this script did not, so the same list passed through one
# and failed through the other. `-w $$` ties it to this process, so it goes
# when this does.
if command -v caffeinate >/dev/null 2>&1; then
    caffeinate -du -w $$ &
fi

# The cases to run. `test.sh` passes its own list, which is the point: a second
# copy of that list here drifted the moment a case was added, and four cases
# went unsanitized without anything saying so. The default is for running this
# script by hand.
cases=("${@:-tree events shelf menu system roles bridge mount}")
[[ $# -gt 0 ]] && cases=("$@")

# The host is one file per concern under src/mac/, so every one of them is
# compiled and every one of them is linked. A glob rather than a list: a file
# added to the host and forgotten here would go unsanitized, which is exactly
# the drift the case list above already had to be cured of.
host_objects=()
for source in "$root"/src/mac/*.m; do
    object="$out/$(basename "${source%.m}").o"
    clang -c -O1 -g -fsanitize=address,undefined -fno-sanitize-recover=undefined \
          -Wall -Wextra -x objective-c "$source" \
          -I "$root/src" -I "$root/src/mac" -o "$object"
    host_objects+=("$object")
done
if [[ ${#host_objects[@]} -eq 0 ]]; then
    echo "sanitize: no host sources in src/mac — the layout moved" >&2
    exit 1
fi

# The frameworks the host needs, read from the manifest rather than copied.
#
# A second list drifts. This script linked AppKit, Foundation and CoreVideo by
# hand, and the day the host started animating — QuartzCore — the whole
# sanitizer leg failed on undefined symbols, long after every other leg had
# gone green. `beans.pot` is where a host says what it links, so that is where
# this reads it from.
frameworks=()
named=0
while read -r name; do
    [[ -n "$name" ]] || continue
    frameworks+=(-framework "$name")
    named=$((named + 1))
done < <(grep -E '^link[[:space:]]+macos[[:space:]]+framework' "$root/beans.pot" \
         | sed -E 's/.*"([^"]+)".*/\1/')
if [[ $named -eq 0 ]]; then
    echo "sanitize: beans.pot names no macOS frameworks — the manifest moved" >&2
    exit 1
fi
# Counted separately, because each one is two words in the array.
echo "sanitize: linking $named frameworks from beans.pot"

failures=0
for name in ${cases[@]}; do
    source="$root/tests/$name.b"
    [[ -f "$source" ]] || { echo "sanitize: no tests/$name.b" >&2; exit 1; }

    # The IR file beansc leaves behind carries a content hash in its name, so
    # the newest one for this program is the one that was just built.
    #
    # **`BEANS_BUILD_JOBS=1` is load-bearing, not a speed setting.** Above
    # about four megabytes of IR, beansc splits a module into eight chunks and
    # compiles them in parallel — there is then no single `.ll` to pick up, and
    # this reads one. One job puts the chunk count back to one. It broke for
    # real: `tests/triangle.b` crossed the threshold the day `cortado.gpu`
    # grew, and the failure was a bare exit with nothing printed, because the
    # guard below could not fire — `set -o pipefail` killed the assignment that
    # was meant to feed it. Hence the `|| true`.
    rm -f "$root/build/$name".*.ll "$root/build/$name".*_ffi.c
    ( cd "$root" && BEANS_SANITIZE=address,undefined BEANS_BUILD_JOBS=1 \
        "$BEANSC" build "tests/$name.b" -o "$out/$name.unused" >/dev/null )
    ir="$(ls -t "$root/build/$name".*.ll 2>/dev/null | head -1 || true)"
    [[ -n "$ir" ]] || { echo "sanitize: beansc emitted no IR for $name" >&2; exit 1; }

    # The foreign-call wrappers and stored-callback trampolines are generated C
    # beside the IR, not part of it. A link without them is a wall of undefined
    # `beans_ffi_wrap_*` symbols, which is how this script failed the first
    # time it ran.
    ffi=()
    bridge="$(ls -t "$root/build/$name".*_ffi.c 2>/dev/null | head -1 || true)"
    [[ -n "$bridge" ]] && ffi+=("$bridge")

    clang -O1 -g -pthread -fsanitize=address,undefined \
          -fno-sanitize-recover=undefined -Wno-override-module \
          "$ir" "$BEANS_RUNTIME" "${host_objects[@]}" "${ffi[@]}" \
          "${frameworks[@]}" \
          -lm -o "$out/$name"

    set +e
    ASAN_OPTIONS=detect_leaks=0 "$out/$name" >"$out/$name.stdout" 2>"$out/$name.stderr"
    status=$?
    set -e

    if grep -Eq 'AddressSanitizer|UndefinedBehaviorSanitizer|runtime error:' \
        "$out/$name.stderr"; then
        echo "FAIL sanitize $name:" >&2
        head -30 "$out/$name.stderr" >&2
        failures=$((failures + 1))
        continue
    fi
    if [[ $status -ne 0 ]]; then
        echo "FAIL sanitize $name: exited $status" >&2
        head -20 "$out/$name.stderr" >&2
        failures=$((failures + 1))
        continue
    fi
    # The instrumented run must produce the same answer as the ordinary one.
    # A sanitizer that changes behaviour has found something even when it says
    # nothing.
    if ! diff -q "$root/tests/$name.out" "$out/$name.stdout" >/dev/null; then
        echo "FAIL sanitize $name: instrumented output differs from the golden" >&2
        diff -u "$root/tests/$name.out" "$out/$name.stdout" | head -20 >&2
        failures=$((failures + 1))
        continue
    fi
    echo "  ok $name"
done

if [[ $failures -gt 0 ]]; then
    echo "sanitize: $failures case(s) failed" >&2
    exit 1
fi
echo "ok sanitize: the macOS host is clean under ASan and UBSan"
