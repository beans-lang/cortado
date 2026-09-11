#!/usr/bin/env bash
# Runs cortado's headless suite under AddressSanitizer and UndefinedBehaviorSanitizer.
#
# `BEANS_SANITIZE` instruments the Beans half, and that is the half a
# sanitizer usually finds nothing in — the compiler's own gate covers it. The
# half worth checking here is `src/cortado_*.m`: fifteen hundred lines of
# Objective-C with manual retain and release, a handle table indexed by
# arithmetic, and a string boundary that copies bytes both ways. `csrc` does
# not pass sanitizer flags to a manifest's C sources, so this script compiles
# the host itself with them and links by hand.
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
beans_tree="$(cd "$(dirname "$BEANSC")/.." && pwd)"
export BEANS_RUNTIME="$beans_tree/runtime/beans_rt.c"
export BEANS_STDLIB="$beans_tree/stdlib/std"
export BEANS_ENCODING="$beans_tree/runtime/encoding"
export BEANS_NET="$beans_tree/runtime/net"
export BEANS_LOG="$beans_tree/runtime/log"

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "SKIP sanitize: the only host written is macOS"
    exit 0
fi

cases=("${@:-tree events shelf menu system roles bridge mount}")
[[ $# -gt 0 ]] && cases=("$@")

host="$out/cortado_macos.o"
clang -c -O1 -g -fsanitize=address,undefined -fno-sanitize-recover=undefined \
      -Wall -Wextra -x objective-c "$root/src/cortado_macos.m" \
      -I "$root/src" -o "$host"

failures=0
for name in ${cases[@]}; do
    source="$root/tests/$name.b"
    [[ -f "$source" ]] || { echo "sanitize: no tests/$name.b" >&2; exit 1; }

    # The IR file beansc leaves behind carries a content hash in its name, so
    # the newest one for this program is the one that was just built.
    rm -f "$root/build/$name".*.ll "$root/build/$name".*_ffi.c
    ( cd "$root" && BEANS_SANITIZE=address,undefined \
        "$BEANSC" build "tests/$name.b" -o "$out/$name.unused" >/dev/null )
    ir="$(ls -t "$root/build/$name".*.ll 2>/dev/null | head -1)"
    [[ -n "$ir" ]] || { echo "sanitize: beansc emitted no IR for $name" >&2; exit 1; }

    # The foreign-call wrappers and stored-callback trampolines are generated C
    # beside the IR, not part of it. A link without them is a wall of undefined
    # `beans_ffi_wrap_*` symbols, which is how this script failed the first
    # time it ran.
    ffi=()
    bridge="$(ls -t "$root/build/$name".*_ffi.c 2>/dev/null | head -1)"
    [[ -n "$bridge" ]] && ffi+=("$bridge")

    clang -O1 -g -pthread -fsanitize=address,undefined \
          -fno-sanitize-recover=undefined -Wno-override-module \
          "$ir" "$BEANS_RUNTIME" "$host" "${ffi[@]}" \
          -framework AppKit -framework Foundation \
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
