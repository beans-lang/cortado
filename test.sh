#!/usr/bin/env bash
# cortado's gate.
#
#     ./test.sh              the interpreter leg, plus cross-target checks
#     ./test.sh --native     also build and run every case as a real binary
#
# Every case prints a widget tree or an event log that was read back off live
# platform objects, and both legs must match the committed golden byte for
# byte. Native output is compared against the golden, never against a fresh
# interpreter run: two wrong answers that agree would otherwise pass.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# The compiler, resolved the way every package in this workspace resolves it.
BEANSC="${BEANSC:-}"
if [[ -z "$BEANSC" ]]; then
    if [[ -n "${BEANS_ROOT:-}" && -x "$BEANS_ROOT/build/beansc" ]]; then
        BEANSC="$BEANS_ROOT/build/beansc"
    elif [[ -x "$root/../../beans/build/beansc" ]]; then
        BEANSC="$root/../../beans/build/beansc"
    else
        BEANSC="$(command -v beansc)"
    fi
fi

# A tree-built beansc resolves its runtime and standard library relative to the
# working directory, so an out-of-tree gate has to name them.
beans_tree="$(cd "$(dirname "$BEANSC")/.." && pwd)"
if [[ -f "$beans_tree/runtime/beans_rt.c" ]]; then
    export BEANS_RUNTIME="$beans_tree/runtime/beans_rt.c"
    export BEANS_STDLIB="$beans_tree/stdlib/std"
    export BEANS_ENCODING="$beans_tree/runtime/encoding"
    export BEANS_NET="$beans_tree/runtime/net"
    export BEANS_LOG="$beans_tree/runtime/log"
fi

native=0
[[ "${1:-}" == "--native" ]] && native=1

# cortado has one platform host so far. Everywhere else the Beans half still
# type-checks — the cross-target leg below proves it — but nothing can run.
host_os="$(uname -s)"
have_host=0
[[ "$host_os" == "Darwin" ]] && have_host=1

# ---------------------------------------------------------------- skip ledger
#
# A gate that quietly skips a leg when its input is missing reads green forever
# once the layout moves under it. Every skip is counted and named, and an
# unannounced one fails the run: to skip a leg on purpose, name it in
# CORTADO_ALLOW_SKIP so the decision is visible in the workflow file rather
# than invisible in a passing log.
skipped=()
skip() {
    echo "SKIP $1: $2"
    skipped+=("$1")
}

legs=0
pass() { legs=$((legs + 1)); }

# Cases that need a platform host. Only macOS has one so far.
cases=(tree events bridge mount shelf menu system roles)

# Cases that need nothing but the language. These are the layout engine, which
# is pure Beans with no foreign call in it at all, so they run on every
# operating system cortado will ever target — including the ones whose host has
# not been written. A layout bug is therefore found by any runner, not only by
# a Mac.
portable=(layout diff)

# ---------------------------------------------------------- the boundary gates
#
# These run first because they are cheap and because everything below them is
# meaningless if the binding and the header have drifted apart.
mkdir -p "$root/build"
"$root/tools/check_abi.sh"
pass
"$root/tools/check_constants.sh"
pass
"$root/tools/check_vocabulary.sh"
pass
"$root/tools/check_hosts.sh"
pass

# ----------------------------------------------------------- portable leg
for name in "${portable[@]}"; do
    golden="$root/tests/$name.out"
    if [[ ! -f "$golden" ]]; then
        echo "FAIL $name: tests/$name.out is missing — a case with no golden proves nothing" >&2
        exit 1
    fi
    "$BEANSC" run "$root/tests/$name.b" >"$tmp/$name.interp" 2>&1
    diff -u "$golden" "$tmp/$name.interp"
    pass
done
echo "ok portable: ${#portable[@]} suites, $(cat "$root/tests/layout.out" "$root/tests/diff.out" | grep -c '^== ') goldens, no display and no FFI"

# ------------------------------------------------------------- interpreter leg
if [[ $have_host -eq 0 ]]; then
    skip runtime "cortado has no host for $host_os yet; only the macOS host is written"
fi
if [[ $have_host -eq 1 ]]; then
for name in "${cases[@]}"; do
    golden="$root/tests/$name.out"
    if [[ ! -f "$golden" ]]; then
        echo "FAIL $name: tests/$name.out is missing — a case with no golden proves nothing" >&2
        exit 1
    fi
    "$BEANSC" run "$root/tests/$name.b" >"$tmp/$name.interp" 2>&1
    diff -u "$golden" "$tmp/$name.interp"
    pass
done
echo "ok interpreter: ${#cases[@]} cases"

# ------------------------------------------------------- the portable golden
#
# `tests/roles.out` is the file that makes "write once, run anywhere" a test
# rather than a claim: a second host prints these same bytes, and that diff is
# the port's definition of done. So it must hold nothing platform-specific, and
# the two ways it could stop being portable are checked here rather than
# discovered at the Windows port.
if grep -qE "NS[A-Z]|Cortado[A-Z]|Gtk|HWND" "$root/tests/roles.out"; then
    echo "FAIL roles: tests/roles.out names a platform's own class." >&2
    echo "     It is the one golden every host must print identically, so it" >&2
    echo "     can hold cortado's vocabulary and nothing else. Native class" >&2
    echo "     names belong in tests/shelf.out, which is per-platform." >&2
    exit 1
fi
if grep -q "native_class" "$root/tests/roles.b"; then
    echo "FAIL roles: tests/roles.b asks for a native class name." >&2
    exit 1
fi
pass
echo "ok roles: the portable golden names no platform"

# ----------------------------------------------------------------- the iOS leg
#
# The same program, built for a phone and run on one. This is the leg that
# turns "write once, run anywhere" from a design claim into a diff: the iOS
# host is a different file implementing the same header, and `tests/roles.out`
# is the bytes both print.
#
# It needs Xcode (not just the Command Line Tools) and a booted simulator, and
# it says which is missing rather than passing quietly.
if [[ "$host_os" == "Darwin" ]]; then
    if ! xcrun --sdk iphonesimulator --show-sdk-path >/dev/null 2>&1; then
        skip ios "no iPhoneSimulator SDK — install Xcode, not just the Command Line Tools"
    # `beansc --help` exits 2, and `set -o pipefail` makes that fail the whole
    # pipeline — so the output is captured first and matched after. A check
    # that mistook a help screen's exit code for "no iOS target" would skip
    # this leg forever and read green.
    elif ! { "$BEANSC" --help 2>&1 || true; } | grep -q "arm64-apple-ios-sim"; then
        skip ios "this beansc has no iOS target; build one from a tree that has it"
    else
        "$BEANSC" build "$root/tests/roles.b" --target arm64-apple-ios-sim \
            -o "$tmp/roles-ios" >"$tmp/ios.build" 2>&1 || {
            echo "FAIL ios: cortado does not build for the simulator" >&2
            tail -20 "$tmp/ios.build" >&2
            exit 1
        }
        pass
        booted="$(xcrun simctl list devices booted 2>/dev/null | grep -oE '[0-9A-F-]{36}' | head -1 || true)"
        if [[ -z "$booted" ]]; then
            skip ios_run "no booted simulator — 'xcrun simctl boot <device>' to run the iOS leg"
            echo "ok ios: cortado builds for the simulator"
        else
            xcrun simctl spawn "$booted" "$tmp/roles-ios" >"$tmp/roles-ios.out" 2>&1
            diff -u "$root/tests/roles.out" "$tmp/roles-ios.out"
            pass
            echo "ok ios: the portable golden is the same bytes on macOS and iOS"
        fi
    fi
fi

# ------------------------------------------------------------- negative control
#
# The headless leg claims a widget tree can be built with nothing on screen. A
# probe that always answered yes would be indistinguishable from one that
# worked, so the control checks that the opposite is detectable: a surface
# shown under AppRole.headless must report itself invisible.
if ! grep -q "is_visible" "$root/tests/headless.b" 2>/dev/null; then
    echo "FAIL negative control: tests/headless.b does not test visibility" >&2
    exit 1
fi
"$BEANSC" run "$root/tests/headless.b" >"$tmp/headless.out" 2>&1
diff -u "$root/tests/headless.out" "$tmp/headless.out"
pass
echo "ok negative control: headless surfaces really are invisible"
fi

# --------------------------------------------------------------- cross-targets
#
# The Beans half of cortado must type-check for every platform cortado intends
# to reach, even before that platform's host exists. A type error that only
# appears at the Windows port is a type error that was always there.
for target in x86_64-pc-windows-gnu aarch64-unknown-linux-gnu; do
    for probe in tree layout diff; do
        "$BEANSC" check "$root/tests/$probe.b" --target "$target" >"$tmp/cross.out" 2>&1 || {
            echo "FAIL cross-check $probe for $target:" >&2
            cat "$tmp/cross.out" >&2
            exit 1
        }
    done
    pass
done
echo "ok cross-target check: windows-gnu, linux-gnu"

# ------------------------------------------------------------------ native leg
if [[ $native -eq 1 ]]; then
    for name in "${portable[@]}"; do
        "$BEANSC" build "$root/tests/$name.b" -o "$tmp/$name.bin" >/dev/null
        "$tmp/$name.bin" >"$tmp/$name.native" 2>&1
        diff -u "$root/tests/$name.out" "$tmp/$name.native"
        pass
    done
    echo "ok native portable: ${#portable[@]} cases"
fi

if [[ $native -eq 1 && $have_host -eq 1 ]]; then
    for name in "${cases[@]}"; do
        "$BEANSC" build "$root/tests/$name.b" -o "$tmp/$name.bin" >/dev/null
        "$tmp/$name.bin" >"$tmp/$name.native" 2>&1
        diff -u "$root/tests/$name.out" "$tmp/$name.native"
        pass
    done
    # The windowed examples are built and linked but never run: they want a
    # display, and a gate must not need one.
    "$BEANSC" build "$root/examples/hello.b" -o "$tmp/hello.bin" >/dev/null
    pass
    # The component example is a separate module, because it names barista as
    # well as cortado. It is built only when barista is checked out beside us —
    # cortado's own core does not depend on it, and a gate that hard-required a
    # sibling repository would be red for anyone who cloned one repo.
    if [[ -f "$root/../barista/beans.pot" ]]; then
        "$BEANSC" build "$root/examples/counter/main.b" -o "$tmp/counter.bin" >/dev/null
        pass
        echo "ok native: ${#cases[@]} cases, and both examples link"
    else
        skip counter_example "barista is not checked out at ../barista, so the dependency-injection example cannot be built"
        echo "ok native: ${#cases[@]} cases, and examples/hello links"
    fi
fi

# ------------------------------------------------------------------- markup
#
# The `.bx` compiler is pure Beans over std.fs — it links no platform host, so
# it builds and runs anywhere. Two things are checked, in this order:
#
#   1. **Drift.** Every generated `_gen.b` is regenerated and diffed against the
#      committed copy. A stale one fails the build instead of shipping, which is
#      what makes checking generated code in safe rather than a liability.
#   2. **The result.** The generated render is mounted headless and its tree is
#      diffed against a golden, so "the markup produced the controls it
#      describes" is a test rather than a screenshot somebody looked at once.
"$BEANSC" build "$root/examples/cortado_bx.b" -o "$tmp/cortado-bx" >/dev/null
pass
# Regenerated from the repository root with a relative path, because the path
# is written into the generated file's header — so the diff has to be run the
# way a person regenerates, or it fails on the absolute path alone.
for source in examples/markup/site/*.bx examples/gallery/site/*.bx; do
    stem="$(basename "${source%.bx}")"
    (cd "$root" && "$tmp/cortado-bx" build "$source" --stdout) >"$tmp/regen.b" 2>"$tmp/regen.err" || {
        echo "FAIL markup: cortado-bx refused $(basename "$source")" >&2
        cat "$tmp/regen.err" >&2
        exit 1
    }
    module="$(dirname "$(dirname "$source")")"
    if ! diff -u "$root/$module/generated/site/$stem.b" "$tmp/regen.b"; then
        echo "FAIL markup: $module/generated/site/$stem.b is stale — regenerate it with" >&2
        echo "    build/cortado-bx build $module/site/*.bx" >&2
        exit 1
    fi
done
pass
# The editor vocabulary is printed from cortado's own tables, so an editor
# cannot describe a language cortado does not have. Committed, and diffed here.
(cd "$root" && "$tmp/cortado-bx" vocabulary) >"$tmp/vocabulary.json" 2>&1
if ! diff -u "$root/bx/vocabulary.json" "$tmp/vocabulary.json"; then
    echo "FAIL markup: bx/vocabulary.json is stale — regenerate it with" >&2
    echo "    build/cortado-bx vocabulary > bx/vocabulary.json" >&2
    exit 1
fi
pass
echo "ok markup: cortado-bx builds, every generated file matches its source, and the editor vocabulary is current"

if [[ $native -eq 1 && $have_host -eq 1 ]]; then
    if [[ -f "$root/../barista/beans.pot" ]]; then
        "$BEANSC" build "$root/examples/markup/main.b" -o "$tmp/markup.bin" >/dev/null
        "$tmp/markup.bin" --dump >"$tmp/markup.out" 2>&1
        diff -u "$root/tests/markup.out" "$tmp/markup.out"
        pass
        # Every control cortado has, in one window, described in markup. This
        # is the file a second host will be read against: when Win32 lands, the
        # same markup produces the same tree with different native classes.
        "$BEANSC" build "$root/examples/gallery/main.b" -o "$tmp/gallery.bin" >/dev/null
        "$tmp/gallery.bin" --dump >"$tmp/gallery.out" 2>&1
        diff -u "$root/tests/gallery.out" "$tmp/gallery.out"
        pass
        echo "ok markup: a .bx screen mounts to real controls, and the gallery shows every one"

        # ---------------------------------------------------------- bundling
        #
        # A bare binary runs and shows a window, which is why the examples work
        # without a bundle. What it does not get is a name in the Dock and the
        # menu bar, a place in Launch Services, an icon, or the ability to be
        # signed — all of which come from an Info.plist. A program nobody can
        # double-click is not shipped.
        #
        # Three things are checked, and the third is the one that matters: the
        # plist parses, the signature verifies, and the running process is
        # named after the bundle. That last one only holds if Launch Services
        # actually read the plist, which is the whole point of making one.
        "$root/tools/bundle.sh" "$tmp/gallery.bin" CortadoGate org.beans-lang.cortado.gate >"$tmp/bundle.log" 2>&1 || {
            echo "FAIL bundle:" >&2; cat "$tmp/bundle.log" >&2; exit 1
        }
        plutil -lint "$tmp/CortadoGate.app/Contents/Info.plist" >/dev/null
        codesign --verify --strict "$tmp/CortadoGate.app"
        open "$tmp/CortadoGate.app"
        named=""
        for _ in 1 2 3 4 5 6 7 8; do
            sleep 1
            if osascript -e 'tell application "System Events" to get name of every process whose name is "CortadoGate"' 2>/dev/null | grep -q CortadoGate; then
                named="yes"
                break
            fi
        done
        osascript -e 'tell application "System Events" to quit (every process whose name is "CortadoGate")' >/dev/null 2>&1 || true
        pkill -f CortadoGate.app >/dev/null 2>&1 || true
        if [[ -z "$named" ]]; then
            echo "FAIL bundle: the bundled app did not run under its bundle name," >&2
            echo "     which means Launch Services did not read the Info.plist." >&2
            exit 1
        fi
        pass
        echo "ok bundle: a .app lints, verifies, and runs under its own name"
    else
        skip markup_mount "barista is not checked out at ../barista, so the markup example cannot be built"
    fi
elif [[ $native -eq 1 ]]; then
    echo "-- native leg not run: no host for $host_os"
else
    echo "-- native leg not requested (pass --native)"
fi

# -------------------------------------------------------------------- verdict
echo
echo "ok cortado: $legs legs"
if [[ ${#skipped[@]} -gt 0 ]]; then
    echo "skipped: ${#skipped[@]} (${skipped[*]})"
    allowed="${CORTADO_ALLOW_SKIP:-}"
    for name in "${skipped[@]}"; do
        if [[ " $allowed " != *" $name "* ]]; then
            echo >&2
            echo "FAIL: leg '$name' was skipped and is not named in CORTADO_ALLOW_SKIP." >&2
            echo "A skip that nobody declared is how a suite goes green while testing nothing." >&2
            exit 1
        fi
    done
    echo "every skip was declared in CORTADO_ALLOW_SKIP"
fi
