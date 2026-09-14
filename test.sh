#!/usr/bin/env bash
# cortado's gate.
#
#     ./test.sh              the interpreter leg, plus cross-target checks
#     ./test.sh --native     also build and run every case as a real binary
#     ./test.sh --sanitize   also run every headless case under ASan and UBSan
#     ./test.sh --case roles  the gates plus one case, on every host that runs it
#
# `--case` exists because the full run has grown to the better part of an hour
# and almost all of it is one leg: the interpreter runs each case as its own
# program, and each program relinks the platform host — sixty C files now. A
# change that touches one control needs one case, so that is the loop while
# writing, and the full run is what goes with a commit. It is not a shortcut
# past anything: all four gates still run, and the named case is run on every
# host that can run it, exactly as the full suite runs it.
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
sanitize=0
only=""
expect_case=0
for argument in "$@"; do
    if [[ $expect_case -eq 1 ]]; then
        only="$argument"
        expect_case=0
        continue
    fi
    case "$argument" in
        --native)   native=1 ;;
        --sanitize) native=1; sanitize=1 ;;
        --case)     expect_case=1 ;;
        *) echo "test.sh: unknown option $argument" >&2; exit 2 ;;
    esac
done
if [[ $expect_case -eq 1 ]]; then
    echo "test.sh: --case needs the name of a case after it" >&2
    exit 2
fi
# A name that is not a case is refused rather than run as an empty list. A
# typo that quietly checked nothing and printed "ok" is the exact failure the
# skip lines in a green run are read for.
if [[ -n "$only" && ! -f "$root/tests/$only.b" ]]; then
    echo "test.sh: there is no tests/$only.b" >&2
    exit 2
fi

# ------------------------------------------------------------- keep the screen
#
# The frame clock is the display's, and a display that has gone to sleep is not
# one: CVDisplayLinkCreateWithActiveCGDisplays answers kCVReturnInvalidArgument
# when there is no active display, so `clock` and `frames` go red on any desk
# machine whose screen blanks part-way through a run. That is not a flake to
# live with — it is a suite that passes or fails depending on how long somebody
# was away from the keyboard.
#
# `-u` asserts user activity, which wakes a screen that has already gone; `-d`
# keeps it from going again; `-w $$` ends the assertion when this script does,
# so nothing is left holding the machine awake afterwards.
if command -v caffeinate >/dev/null 2>&1; then
    caffeinate -du -w $$ &
fi

# Which host `beansc` will pick for this machine. Three are written — AppKit,
# UIKit and GTK4 — but the manifest chooses by target OS, so only the AppKit
# one is reachable by a plain build here. The GTK4 leg below links its host by
# hand; everywhere else the Beans half still type-checks, which the
# cross-target leg proves, but nothing can run.
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
cases=(tree events attributes bridge mount nested slots shelf menu system roles text pixels applied leaks enabled checked controls numbers strings table outline input surface machine gated pickers panes shell web page permission icons opacity styled custom clock clocks frames anim gpu triangle shapes canvas shader named_gradients)

# The cases whose golden names nothing a platform gets to decide, so every host
# must print them byte for byte. This is the list that makes "write once, run
# anywhere" a diff rather than a claim, and it is deliberately more than
# `roles`: a tree of controls agreeing says nothing about whether two hosts
# agree on *which event a control raises*, on what survives a round trip
# through their text APIs, or on what a teardown releases.
#
# `enabled` is here because it is the case that caught four hosts answering
# four different things. It is a property whose *set of widgets* is part of the
# contract, and nothing else in the suite could see a disagreement about it:
# `roles` reads the state with a match that treats a refusal and "enabled" the
# same, so a host that refused printed identical bytes to one that accepted.
#
# It prints the *rule* per kind and then a count of the controls that obey it,
# rather than one observed line per control — and that shape was forced rather
# than chosen. The observed form worked for exactly as long as every host had
# every kind, and stopped the day a level indicator landed: UIKit has none, so
# iOS printed "is not a control on this platform" where macOS printed a
# refusal, and a golden meant to be identical on four hosts was reporting an
# inventory. Which controls exist is `controls`'s business.
#
# `checked` and `controls` are here for the reason `enabled` is, and they were
# written because the same mistake had been made a second time without anybody
# noticing. `CTD_P_CHECKED` was still being answered by each host asking its own
# object system, so a push button could be ticked on macOS and nowhere else,
# and a radio button asked for the mixed state got four different answers. No
# case in this suite wrote that property to a control that was not a check box,
# so nothing could see it.
#
# `controls` is the file that can name a control one platform has not got. It
# is portable because it prints agreement rather than inventory: a host with a
# switch builds one, a host without refuses by name, and the same bytes come
# out of both. The alternative — a per-platform golden of what exists — leaves
# the refusing host unchecked, which is exactly where a silent substitution
# would hide.
#
# `anim` is here because an animation is mostly a set of decisions — which
# refusals, what the property reads while it moves, what cancelling keeps, what
# happens to the one it replaces — and a decision is not allowed to differ
# between platforms. That two hosts print the same bytes while one hands the
# description to Core Animation and the other walks the curve itself is the
# strongest thing this suite says.
#
# `slots` is here with `nested` and for the same reason. Which component a
# child key belongs to is arithmetic on strings — the component that is
# rendering, and the fragment placement the key was asked for inside — and a
# platform gets no say in it. Its golden is what each component wrote as it
# rendered plus the text that reached the controls, so a host that collapsed
# two children into one would print the wrong words rather than a wrong class
# name. It is also the case that cannot be built from one of anything: one
# placement, one component or one level of nesting each passes against a scheme
# that is wrong, which is why it places one template twice, puts a fragment
# between two sibling tags, and places a fragment inside a fragment.
#
# `clock` is here for the same kind of reason as `enabled`: a frame clock is
# arithmetic — a number, a token, an elapsed time, and a set of refusals — and
# arithmetic is not allowed to differ between platforms. It can be in this list
# at all because the host can raise a frame on demand; a case that waited for a
# display could only ever run on one host, and on none of the build machines.
#
# The four that are not here are not here for a reason. `mount` and `bridge`
# measure real controls, and a control is allowed to refuse the size it is
# given — iOS established that and GTK confirmed it. `pixels` reads a widget
# back as pixels, which only macOS can do, so its golden is the macOS answer
# and every other host correctly prints that it cannot. `frames` runs a real
# display link, which a window that is never shown only has on macOS.
# `gpu` is here, and it is the only case in this list whose two sides run
# entirely different code. macOS and iOS open a Metal device, read its name and
# three limits and close it; GTK4 and Win32 refuse all four. Every line of its
# golden asks whether what happened agrees with what `Capability.gpu` promised,
# so the same bytes come out of both — which is a stronger claim than either
# side alone, and it is the one that matters: a platform that cannot draw with
# shaders says so, and never quietly does nothing. `tests/pixels.b` shows the
# alternative, where the refusing hosts go unchecked.
cross_host=(roles attributes nested slots styled custom events text applied leaks enabled checked controls numbers strings table outline input surface machine gated pickers panes shell web permission icons opacity clock clocks anim gpu canvas shader named_gradients)

# Cases that run on macOS and iOS and nowhere else.
#
# `cross_host` is for goldens every host prints. This is the other shape: a
# case only the hosts with a GPU can run at all, whose golden is still worth
# comparing between the two that can. `triangle` draws quads onto pixel
# boundaries and asserts the colours exactly — and those colours came back the
# same through this Mac's GPU and through the Simulator's, which are different
# hardware with different limits. That equality is what this list exists to
# keep checking.
#
# GTK4 and Win32 are not missing from it by omission. They have no GPU host,
# `tests/gpu.b` is where that is checked, and a case that asserted a green
# pixel could only ever print a refusal there.
apple_only=(triangle shapes)

# Cases the iOS leg builds but does not run, and why.
#
# `anim` is here because of something only a probe could have told us: on iOS a
# layer that is not in a visible window has no render context, and Core
# Animation removes an animation on one within a frame and reports that it did
# not finish. Proven both ways in a bare simulator process — with
# `makeKeyAndVisible` the same animation runs, the presentation layer reads
# three quarters of the way through a fade at 50 ms, and the delegate is told
# it finished; without, it is gone at once. macOS has no such rule: an AppKit
# layer animates in a window that was never ordered front, which is why the
# rest of this suite can be headless at all.
#
# cortado's gate is headless everywhere, so it cannot watch an iOS animation
# run. The case is still built for the phone, which is what catches a Beans
# half that does not compile there, and a real application — which shows its
# window — animates exactly as macOS does.
ios_builds_only=(anim)

# Cases that need nothing but the language. These are the layout engine, the
# reconciler and the markup compiler, all pure Beans with no foreign call in
# them at all, so they run on every operating system cortado will ever target —
# including the ones whose host has not been written. A layout, differ or
# markup bug is therefore found by any runner, not only by a Mac.
#
# `sweep` is the randomized one: four hundred generated tree pairs, diffed and
# then re-applied by a second implementation written inside the test, asserting
# that applying a diff to the old tree reaches the new one. Its golden carries
# the tally of edits it produced, so a sweep that stopped generating moves is
# visible rather than quietly green.
#
# `markup_refusals` is the one that reads `cortado.bx` directly, because what it
# asserts has no other way in: a refusal's *message*. Half of these forms were
# refused before and after the change — `attrs=` on a control was already an
# unknown attribute — so a check that counted refusals would pass with the whole
# thing reverted. It is here rather than beside the `markup` leg because the
# markup compiler links no platform host, which is the property that lets a
# Windows machine regenerate a project's screens.
#
# `placed` is here for the same reason, and it started out in the wrong list.
# `insets` and `placement` are the same shape again: per-edge insets, and what
# a component tag carries, each from the attribute to the solved frame.
# It was written reading frames off real controls and put in `cross_host` on
# the claim that a coordinate is arithmetic — which is true of the coordinate
# and not of the frame: an unmapped GTK4 widget has no allocation and answered
# 0,0 for every child. Where a child ends up is AbsoluteLayout's, and
# `tests/layout.b` already holds it. What is left is the step before, which
# really is arithmetic: that `x={10}` reaches `spec.x`, and that a coordinate
# written where nothing reads one is refused rather than dropped.
portable=(layout diff sweep markup_refusals placed insets placement)

# `--case` narrows every list to the one name, and leaves the lists it is not
# in empty — so a case that is macOS-only runs on macOS and the GTK4 loop runs
# zero times, which is what it would have done anyway. The line it prints says
# which lists the case was in, because a leg that ran nothing and printed `ok`
# is the silent green this suite is built to avoid.
#
# Written as four plain loops rather than `mapfile`, which macOS's own bash 3.2
# does not have, and without `printf '%s\n' "${empty[@]}"`, which prints one
# empty line that reads back as a one-element array holding "" — a leg then
# runs `tests/.b` and says so in a way that takes a minute to understand.
if [[ -n "$only" ]]; then
    in_lists=""
    kept=()
    for name in "${portable[@]}"; do
        if [[ "$name" == "$only" ]]; then kept+=("$name"); fi
    done
    portable=("${kept[@]+"${kept[@]}"}")
    if [[ ${#portable[@]} -gt 0 ]]; then in_lists="$in_lists portable"; fi

    kept=()
    for name in "${cases[@]}"; do
        if [[ "$name" == "$only" ]]; then kept+=("$name"); fi
    done
    cases=("${kept[@]+"${kept[@]}"}")
    if [[ ${#cases[@]} -gt 0 ]]; then in_lists="$in_lists interpreter"; fi

    kept=()
    for name in "${cross_host[@]}"; do
        if [[ "$name" == "$only" ]]; then kept+=("$name"); fi
    done
    cross_host=("${kept[@]+"${kept[@]}"}")
    if [[ ${#cross_host[@]} -gt 0 ]]; then in_lists="$in_lists gtk4 ios"; fi

    kept=()
    for name in "${apple_only[@]}"; do
        if [[ "$name" == "$only" ]]; then kept+=("$name"); fi
    done
    apple_only=("${kept[@]+"${kept[@]}"}")
    if [[ ${#apple_only[@]} -gt 0 ]]; then in_lists="$in_lists apple"; fi

    if [[ -z "$in_lists" ]]; then
        echo "test.sh: tests/$only.b exists but is in no list — add it to cases" >&2
        exit 2
    fi
    echo "-- only tests/$only.b:$in_lists (the gates and the build legs still run)"
fi

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
# Counted from the two suites that record a case per section. `sweep` records
# one line for four hundred generated pairs, so it is named separately rather
# than folded into a number it contributes nothing to — a count that reads as
# if it covered every suite is how a suite stops covering anything unnoticed.
if [[ ${#portable[@]} -eq 0 ]]; then
    echo "-- no portable suite in this run"
else
    echo "ok portable: ${#portable[@]} suites, $(cat "$root/tests/layout.out" "$root/tests/diff.out" | grep -c '^== ') recorded cases, $(grep -c '^  ' "$root/tests/markup_refusals.out") markup forms and a $(grep -oE '^sweep: [0-9]+' "$root/tests/sweep.out" | grep -oE '[0-9]+')-case sweep, no display and no FFI"
fi

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
if [[ ${#cases[@]} -eq 0 ]]; then
    echo "-- no host case in this run"
else
    echo "ok interpreter: ${#cases[@]} cases"
fi

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

# ------------------------------------------------------------- the Android leg
#
# cortado's portable half — the layout solver — has no foreign call in it at
# all, so it builds for a phone with no host at all and runs there. That is the
# design claim `cortado.layout` was written to make, and this is the diff that
# tests it: 69 goldens, the same bytes on a Mac and on an Android device.
#
# The component layer is *not* here, and cannot be: it reaches `cortado.host`,
# and there is no Android host. That is M10's work and it is JNI, not this.
if [[ -n "${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}" ]]; then
    if ! { "$BEANSC" --help 2>&1 || true; } | grep -q "aarch64-linux-android"; then
        skip android "this beansc has no Android target"
    else
        "$BEANSC" build "$root/tests/layout.b" --target aarch64-linux-android \
            -o "$tmp/layout-android" >"$tmp/android.build" 2>&1 || {
            echo "FAIL android: the layout engine does not build for Android" >&2
            tail -20 "$tmp/android.build" >&2
            exit 1
        }
        pass
        adb="${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb"
        if [[ ! -x "$adb" ]] || ! "$adb" shell true >/dev/null 2>&1; then
            skip android_run "no device or emulator attached"
            echo "ok android: the layout engine builds for Android"
        else
            "$adb" push "$tmp/layout-android" /data/local/tmp/cortado_layout >/dev/null 2>&1
            "$adb" shell chmod 755 /data/local/tmp/cortado_layout >/dev/null 2>&1
            "$adb" shell /data/local/tmp/cortado_layout 2>&1 | tr -d '\r' >"$tmp/layout-android.out"
            "$adb" shell rm -f /data/local/tmp/cortado_layout >/dev/null 2>&1 || true
            diff -u "$root/tests/layout.out" "$tmp/layout-android.out"
            pass
            echo "ok android: the layout goldens are the same bytes on Android"
        fi
    fi
fi

# ---------------------------------------------------------------- the GTK4 leg
#
# The third implementation of the header, and the one that is not an Apple
# object system: GObject rather than Objective-C, signals rather than
# target/action, floating references rather than retain/release. GTK4 ships a
# macOS backend, so it can be built and run here — which is the only way a
# Linux host could be checked at all before anyone puts cortado on a Linux box.
#
# What it proves is that `tests/roles.out` is the same bytes through a host
# that shares no line of code with the AppKit one. What it cannot prove is
# anything about X11 or Wayland, which are not on this machine.
#
# beansc picks a host from the manifest by target OS, and on a Mac that is the
# AppKit one, so `tools/gtk4.sh` asks beansc for the IR and links the GTK4 host
# beside it by hand.
if ! command -v pkg-config >/dev/null 2>&1 || ! pkg-config --exists gtk4 2>/dev/null; then
    skip gtk4 "no gtk4 on pkg-config's path — 'brew install gtk4' or the distro package"
else
    for name in "${cross_host[@]}"; do
        bash "$root/tools/gtk4.sh" "$name"
        pass
    done
fi

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
        for name in "${cross_host[@]}" "${apple_only[@]}"; do
            "$BEANSC" build "$root/tests/$name.b" --target arm64-apple-ios-sim \
                -o "$tmp/$name-ios" >"$tmp/ios.build" 2>&1 || {
                echo "FAIL ios: tests/$name.b does not build for the simulator" >&2
                tail -20 "$tmp/ios.build" >&2
                exit 1
            }
            pass
        done
        booted="$(xcrun simctl list devices booted 2>/dev/null | grep -oE '[0-9A-F-]{36}' | head -1 || true)"
        if [[ -z "$booted" ]]; then
            skip ios_run "no booted simulator — 'xcrun simctl boot <device>' to run the iOS leg"
            echo "ok ios: $(( ${#cross_host[@]} + ${#apple_only[@]} )) cases build for the simulator"
        else
            ran=0
            for name in "${cross_host[@]}" "${apple_only[@]}"; do
                if [[ " ${ios_builds_only[*]} " == *" $name "* ]]; then continue; fi
                xcrun simctl spawn "$booted" "$tmp/$name-ios" >"$tmp/$name-ios.out" 2>&1
                diff -u "$root/tests/$name.out" "$tmp/$name-ios.out"
                ran=$((ran + 1))
                pass
            done
            echo "ok ios: $ran goldens are the same bytes on macOS and iOS"
            echo "   (${ios_builds_only[*]} built for the phone but not run there — see ios_builds_only)"
        fi
    fi
fi

# --------------------------------------------------------- Metal API validation
#
# The GPU host is the only part of cortado that hands raw objects to a driver
# and manages their lifetimes by hand, and Metal ships a validation layer that
# catches exactly the misuse that costs: an encoder used after it ended, a
# resource released while a command buffer still references it, a descriptor
# with a field the pipeline cannot honour. ASan sees none of that — the memory
# is all valid, it is the *order* that is wrong.
#
# It earned this leg on the day it was added. A pipeline built for an
# off-screen target and used on a canvas is a pixel-format mismatch, which
# Metal on Apple silicon **silently tolerates** — the two formats are the same
# bits with a swizzle the hardware does for free, every golden passed, and the
# colours came back right. Under validation it is an assertion naming both
# formats. Every other backend this ABI is shaped for would refuse it outright,
# so a guard that looked untestable here is the one keeping cortado portable.
#
# What this leg does **not** prove is that `ctd_gpu_pass_end` waits for the GPU
# before the pixels are read. Removing that wait passes at full speed, because
# the readback happens to lose a race it should not be running at all, and it
# fails under validation only because validation is slower. A test tuned to
# lose a race would go quietly green on faster hardware, which is worse than
# not having one. The wait stays because Metal's contract requires it, and that
# is written beside it in src/mac/gpu.m.
if [[ "$host_os" == "Darwin" && $have_host -eq 1 ]]; then
    for name in gpu triangle canvas shader; do
        MTL_DEBUG_LAYER=1 MTL_DEBUG_LAYER_ERROR_MODE=assert \
            "$BEANSC" run "$root/tests/$name.b" 2>&1 \
            | grep -v 'Metal API Validation' >"$tmp/$name.validated"
        diff -u "$root/tests/$name.out" "$tmp/$name.validated"
        pass
    done
    echo "ok metal: 4 cases clean under Metal API Validation"
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

# ------------------------------------------------------------- the Windows host
#
# The fourth implementation of the header, compiled. It is not *run* here —
# there is no Windows machine under this script and the leg does not pretend
# otherwise — but it is linked into a real PE32+ executable against the real
# Win32 host, which is the difference between "the Windows port exists" and
# "the Windows port was written".
#
# **This leg exists because the Windows host silently stopped compiling.**
# `tools/win32.sh` was written, worked, and was never wired into the gate;
# some later commit put a call to `ctd_resolve` into `src/win32/gpu.c`, which
# is a macOS-host function that does not exist there, and nothing noticed for
# as long as nobody typed the script's name by hand. A host nothing builds is
# a host that is already broken and has not been told yet.
if ! command -v x86_64-w64-mingw32-gcc >/dev/null 2>&1; then
    skip win32 "no mingw-w64 on the path — 'brew install mingw-w64' to build the Windows host"
else
    bash "$root/tools/win32.sh"
    pass
fi

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
    # display, and a gate must not need one. An example that is not built is an
    # example that goes stale, and the first person to find out is whoever
    # copied it.
    for example in hello clock shader canvas signin brew ledger finder about settings permissions booking outline notebook panes shelf_bar browser; do
        "$BEANSC" build "$root/examples/$example.b" -o "$tmp/$example.bin" >/dev/null
        pass
    done
    # `shader` is the one example that is also *run*, because it is the one
    # that needs no display: it opens the GPU, renders a Mandelbrot set into an
    # off-screen target and writes it out. Its output names one machine — a GPU
    # by name, a size in bytes — so there is no golden, and what is asserted is
    # that it drew something the size it meant to and said where it put it.
    ( cd "$tmp" && mkdir -p build && "$tmp/shader.bin" ) >"$tmp/shader.out" 2>&1
    grep -q "rendered 640x480, 1228800 bytes" "$tmp/shader.out"
    grep -q "^wrote build/mandelbrot.bmp" "$tmp/shader.out"
    # 640 * 480 * 3 padded to a multiple of four, plus a 54-byte header.
    [[ "$(wc -c <"$tmp/build/mandelbrot.bmp" | tr -d ' ')" == "921654" ]]
    pass
    # The component example is a separate module, because it names barista as
    # well as cortado. It is built only when barista is checked out beside us —
    # cortado's own core does not depend on it, and a gate that hard-required a
    # sibling repository would be red for anyone who cloned one repo.
    if [[ -f "$root/../barista/beans.pot" ]]; then
        "$BEANSC" build "$root/examples/counter/main.b" -o "$tmp/counter.bin" >/dev/null
        pass
        echo "ok native: ${#cases[@]} cases, and every example links"
    else
        skip counter_example "barista is not checked out at ../barista, so the dependency-injection example cannot be built"
        echo "ok native: ${#cases[@]} cases, and every example but the barista one links"
    fi

    # The database browser. A separate module, because it names a second
    # library — and the only example here that is a whole application rather
    # than one control in a window. It is *run*, not merely built: `--dump`
    # opens a database, reads its catalogue, lays the window out headlessly
    # and prints the tree, so the thing being checked is that a real program
    # against this control set still works, not that it still compiles.
    #
    # Its golden names this platform's classes, like the gallery's does, and
    # for the same reason: it is the macOS native leg that runs it. What it is
    # for is the layout — five tab pages, two split views and a tree, all
    # solved against a real window — which is where every bug this example
    # found showed up.
    #
    # The vendored SQLite's version is rewritten out before the diff. It is in
    # the status line because a person wants to see it, and pinning it in a
    # golden would mean this suite goes red the next time the sqlite package
    # updates, which is news about a different repository.
    #
    # `../sqlite`, a sibling of this repository — which is where the workspace
    # puts it and where `examples/cask/beans.pot` looks for it. The guard first
    # written here said `../../sqlite`, one directory too far up, so it matched
    # nothing and this leg skipped on every run it has ever had. That is the
    # shape a dead guard takes: it never fails, it never runs, and everything
    # stays green. The suite refuses an undeclared skip, which is the only
    # reason it was ever noticed.
    if [[ -f "$root/../sqlite/beans.pot" ]]; then
        "$BEANSC" build "$root/examples/cask/main.b" -o "$tmp/cask.bin" >/dev/null
        "$tmp/cask.bin" --dump 2>&1 | sed -E 's/SQLite [0-9]+\.[0-9]+\.[0-9]+/SQLite x.y.z/g' >"$tmp/cask.out"
        diff -u "$root/tests/cask.out" "$tmp/cask.out"
        pass
        echo "ok native: the database browser builds, opens a database and lays itself out"

        # **And through the tree interpreter, which is the half that was
        # missing.** This leg built cask and ran the binary, and nothing ever
        # ran it the other way — so `beansc run examples/cask/main.b` failed
        # for as long as cask has existed, with `bind_text: bad parameter or
        # other API misuse`, and the suite was green throughout.
        #
        # What it was: the interpreter resolved a program's extern symbols
        # against the process's global namespace before the program's own C
        # library, so a package that vendors SQLite got macOS's — dragged in by
        # AppKit — to prepare its statements, and its own to bind them. Two
        # SQLite libraries, one statement. The native backend never had it,
        # because the linker binds the vendored copy at link time.
        #
        # This is the only case in the suite where two packages that each ship
        # C are in one program, which is why nothing else caught it either.
        "$BEANSC" run "$root/examples/cask/main.b" -- --dump 2>&1 \
            | sed -E 's/SQLite [0-9]+\.[0-9]+\.[0-9]+/SQLite x.y.z/g' >"$tmp/cask.interp"
        diff -u "$root/tests/cask.out" "$tmp/cask.interp"
        pass
        echo "ok interpreter: the database browser reads the same database through the tree engine"
    else
        skip cask_example "the sqlite package is not checked out beside this one at ../sqlite, so the database browser cannot be built"
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
# The generated header names its source **relative to that source's module
# root**, so these bytes are the same whichever directory the tool is run from
# and however the path was spelled. That is checked below rather than assumed.
# Found with `find`, not with a shell glob, and that is the point: `site/*.bx`
# is not recursive, so a component somebody put in `site/parts/` would never be
# regenerated and never be diffed. What that produces is the worst failure this
# repository has — a *stale* generated file that still compiles, still renders
# last week's screen, and says nothing.
# Each example names its own markup folder, because a project does — which is
# why the mirror hangs off the module root and not off a folder called `site`.
markup_roots=(examples/markup/site examples/gallery/site examples/gradients/site examples/cask/screens)
for source in $(find "${markup_roots[@]}" -name '*.bx' | sort); do
    module="${source%/*}"
    while [[ "$module" == */* && ! -f "$root/$module/beans.pot" ]]; do
        module="${module%/*}"
    done
    relative="${source#"$module/"}"
    target="$module/generated/${relative%.bx}.b"
    (cd "$root" && "$tmp/cortado-bx" build "$source" --stdout) >"$tmp/regen.b" 2>"$tmp/regen.err" || {
        echo "FAIL markup: cortado-bx refused $source" >&2
        cat "$tmp/regen.err" >&2
        exit 1
    }
    if ! diff -u "$root/$target" "$tmp/regen.b"; then
        echo "FAIL markup: $target is stale — regenerate it with" >&2
        echo "    build/cortado generate ${source%/*}" >&2
        exit 1
    fi
done
pass

# And the tool's own walk finds what `find` found. The loop above is only as
# good as the list it iterates; this is the half that checks cortado-bx agrees
# about what is in a folder, which is what a person actually hands it.
for folder in "${markup_roots[@]}"; do
    (cd "$root" && "$tmp/cortado-bx" build "$folder" --stdout) >"$tmp/walk.b" 2>&1 || {
        echo "FAIL markup: cortado-bx refused the directory $folder" >&2
        cat "$tmp/walk.b" >&2
        exit 1
    }
    walked="$(grep -c '^// Generated from ' "$tmp/walk.b" || true)"
    present="$(find "$root/$folder" -name '*.bx' | wc -l | tr -d ' ')"
    if [[ "$walked" != "$present" ]]; then
        echo "FAIL markup: cortado-bx walked $walked .bx files under $folder, there are $present" >&2
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

# ----------------------------------------------------------------- commands
#
# `@command` on a method, read. It replaced two hand-written tables — the
# menu's rows and the router's token-to-method match — so what has to hold is
# that the one declaration still produces both: the platform builds the
# command, and choosing it runs the method it was written on. A check that
# only counted the commands would pass with the routing deleted.
#
# It lives in `app/tests/` because `cortado_app` is a sibling module: a package
# under `cortado/` may not import its own module root, so the composition root
# cannot live there, and neither can its test.
if [[ -f "$root/../barista/beans.pot" && $have_host -eq 1 ]]; then
    "$BEANSC" run "$root/app/tests/commands.b" >"$tmp/commands.out" 2>&1
    diff -u "$root/app/tests/commands.out" "$tmp/commands.out"
    pass
    if [[ $native -eq 1 ]]; then
        "$BEANSC" build "$root/app/tests/commands.b" -o "$tmp/commands.bin" >/dev/null
        "$tmp/commands.bin" >"$tmp/commands.native" 2>&1
        diff -u "$root/app/tests/commands.out" "$tmp/commands.native"
        pass
    fi
    echo "ok commands: @command builds the menu, and choosing one runs its method"
else
    if [[ $have_host -eq 1 ]]; then
        skip commands "barista is not checked out beside this one at ../barista, so cortado_app cannot be built"
    else
        skip commands "this platform has no cortado host, so a menu cannot be built"
    fi
fi

# ---------------------------------------------------------------------- cli
#
# `cortado` is the project command line: it scaffolds a project, regenerates
# its markup, compiles it with a named profile, and runs it. What this leg
# asserts is the part a person cannot see by looking — that the project it
# writes actually builds and renders, that Debug and Release are two different
# builds and not two names for one, and that a generated file which has fallen
# behind its markup is caught rather than shipped.
"$BEANSC" build "$root/examples/cortado_cli.b" -o "$tmp/cortado" >/dev/null
pass

# The same bytes from two directories and two spellings. The generated header
# names its source, so a header that quoted whatever it was handed would make
# the output depend on the working directory — and then a drift gate reports a
# file stale because somebody ran the tool from one directory up.
(cd "$root" && "$tmp/cortado" generate examples/markup/site --stdout) >"$tmp/spell-a.b"
(cd "$root/examples/markup" && "$tmp/cortado" generate ./site --stdout) >"$tmp/spell-b.b"
if ! diff -u "$tmp/spell-a.b" "$tmp/spell-b.b"; then
    echo "FAIL cli: generating the same markup from two directories wrote two different files" >&2
    exit 1
fi
pass

if [[ -f "$root/../barista/beans.pot" && $have_host -eq 1 ]]; then
    demo="$tmp/cli-demo"
    mkdir -p "$demo"
    (cd "$demo" && "$tmp/cortado" init acme --cortado "$root") >"$tmp/init.out" 2>&1 || {
        echo "FAIL cli: init refused" >&2
        cat "$tmp/init.out" >&2
        exit 1
    }
    pass

    # A screen in a folder the scaffold did not write, one level deeper than
    # anything it did. A walk that is not recursive misses this, and a mirror
    # that flattens puts it in the wrong package — and both failures produce a
    # file that still compiles, which is why the assertion is on the rendered
    # tree and not on the file's existence.
    mkdir -p "$demo/acme/screens/parts"
    cat >"$demo/acme/screens/parts/note.bx" <<'NOTE'
<Label font_size={11}>$self.line</Label>
<beans>
package parts

import cortado.component
import {view, param} from cortado.annotations

@view
pub partial class Note extends component.Component {
    @param pub line: string = ""

    pub fn init() { super.init() }
}
</beans>
NOTE
    # And the screen above it reaches the nested package with one import line.
    python3 - "$demo/acme/screens/home.bx" <<'PATCH'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
s = p.read_text()
s = s.replace('  <Badge words="tap Change for another drink" />',
              '  <Badge words="tap Change for another drink" />\n  <Note line="a screen in a nested folder" />')
s = s.replace('import {Badge} from acme.generated.components',
              'import {Badge} from acme.generated.components\nimport {Note} from acme.generated.screens.parts')
p.write_text(s)
PATCH

    (cd "$demo/acme" && "$tmp/cortado" generate) >/dev/null 2>&1 || {
        echo "FAIL cli: generate refused after a screen was added" >&2
        exit 1
    }
    if [[ ! -f "$demo/acme/generated/screens/parts/note.b" ]]; then
        echo "FAIL cli: the nested screen was not mirrored — the walk is not recursive" >&2
        exit 1
    fi
    (cd "$demo/acme" && "$tmp/cortado" check --drift) >/dev/null 2>&1 || {
        echo "FAIL cli: a freshly generated project reads as stale" >&2
        exit 1
    }
    pass

    # Debug and Release are two builds, not two names. The debug map is the
    # macOS answer to "is there debug information in here": `-g` leaves DWARF
    # in the object files and a `N_OSO` entry per object in the binary, and a
    # release build has none at all. A profile that passed the same flags
    # twice would print the same number here.
    (cd "$demo/acme" && "$tmp/cortado" build) >/dev/null 2>&1
    (cd "$demo/acme" && "$tmp/cortado" build -c Release) >/dev/null 2>&1
    for shape in debug release; do
        if [[ ! -x "$demo/acme/build/$shape/Acme" ]]; then
            echo "FAIL cli: build/$shape/Acme was not produced" >&2
            exit 1
        fi
    done
    debug_oso="$(nm -pa "$demo/acme/build/debug/Acme" 2>/dev/null | grep -c ' OSO ' || true)"
    release_oso="$(nm -pa "$demo/acme/build/release/Acme" 2>/dev/null | grep -c ' OSO ' || true)"
    if [[ "$debug_oso" -eq 0 ]]; then
        echo "FAIL cli: the Debug build carries no debug information ($debug_oso debug-map entries)" >&2
        exit 1
    fi
    if [[ "$release_oso" -ne 0 ]]; then
        echo "FAIL cli: the Release build carries debug information ($release_oso debug-map entries)" >&2
        exit 1
    fi
    pass

    # What the scaffolded application actually renders. The window is 420 by
    # 260 because `@window` on `Home` says so — an annotation that was declared
    # for this and read by nothing until now, so a regression here is silent
    # everywhere else.
    "$demo/acme/build/debug/Acme" --dump >"$tmp/cli.out" 2>&1
    diff -u "$root/tests/cli.out" "$tmp/cli.out"
    pass

    # A generated file that has fallen behind. This is the failure the whole
    # tool exists to make impossible, so it is checked by causing it.
    printf '\n// touched\n' >>"$demo/acme/generated/screens/home.b"
    if (cd "$demo/acme" && "$tmp/cortado" check --drift) >/dev/null 2>&1; then
        echo "FAIL cli: a stale generated file read as current" >&2
        exit 1
    fi
    # And a build puts it back, because a build regenerates first.
    (cd "$demo/acme" && "$tmp/cortado" build) >/dev/null 2>&1
    (cd "$demo/acme" && "$tmp/cortado" check --drift) >/dev/null 2>&1 || {
        echo "FAIL cli: a build did not regenerate a stale file" >&2
        exit 1
    }
    pass

    # A `.bx` outside every markup folder. A screen nothing regenerates is the
    # same silent staleness by another road, so it is an error and not a file
    # quietly left alone.
    mkdir -p "$demo/acme/elsewhere"
    cp "$demo/acme/screens/parts/note.bx" "$demo/acme/elsewhere/stray.bx"
    if (cd "$demo/acme" && "$tmp/cortado" build) >/dev/null 2>&1; then
        echo "FAIL cli: markup outside every markup folder was accepted" >&2
        exit 1
    fi
    rm -rf "$demo/acme/elsewhere"

    # An unknown row in cortado.pot names the line rather than being ignored.
    cp "$demo/acme/cortado.pot" "$tmp/cortado.pot.keep"
    printf 'identfier com.example.typo\n' >>"$demo/acme/cortado.pot"
    if (cd "$demo/acme" && "$tmp/cortado" build) >"$tmp/typo.out" 2>&1; then
        echo "FAIL cli: a misspelled cortado.pot row was ignored" >&2
        exit 1
    fi
    if ! grep -q 'identfier' "$tmp/typo.out"; then
        echo "FAIL cli: the refusal did not name the row it refused" >&2
        cat "$tmp/typo.out" >&2
        exit 1
    fi
    cp "$tmp/cortado.pot.keep" "$demo/acme/cortado.pot"
    pass

    # `clean` removes what was built and leaves what was written. `generated/`
    # is checked in — a clone builds from it with plain `beansc` — so removing
    # it is asked for by name.
    (cd "$demo/acme" && "$tmp/cortado" clean) >/dev/null 2>&1
    if [[ -d "$demo/acme/build" ]]; then
        echo "FAIL cli: clean left the build directory" >&2
        exit 1
    fi
    if [[ ! -f "$demo/acme/generated/screens/home.b" ]]; then
        echo "FAIL cli: clean removed generated/, which is checked-in source" >&2
        exit 1
    fi
    (cd "$demo/acme" && "$tmp/cortado" clean --generated) >/dev/null 2>&1
    if [[ -d "$demo/acme/generated" ]]; then
        echo "FAIL cli: clean --generated left generated/" >&2
        exit 1
    fi
    pass
    echo "ok cli: a scaffolded project builds, renders, and cannot go stale"
else
    if [[ $have_host -eq 1 ]]; then
        skip cli_project "barista is not checked out beside this one at ../barista, so a scaffolded project cannot be built"
    else
        skip cli_project "this platform has no cortado host, so a scaffolded application cannot be linked"
    fi
fi

# `tools/install.sh` is how a person gets `cortado` at all, and it is the one
# script in here that nothing else runs — which is exactly how it shipped
# unable to build anything. It compiles from cortado's directory rather than
# the compiler's, and a tree-built beansc resolves BEANS_RUNTIME relative to
# the working directory, so without the roots it names it dies before writing
# a byte. Installing into a scratch directory and running what landed is the
# only thing that can tell.
installed="$tmp/installed"
if ! "$root/tools/install.sh" "$installed" >"$tmp/install.log" 2>&1; then
    echo "FAIL install: tools/install.sh did not install" >&2
    cat "$tmp/install.log" >&2
    exit 1
fi
for name in cortado cortado-bx; do
    if [[ ! -x "$installed/$name" ]]; then
        echo "FAIL install: $name is not in $installed" >&2
        exit 1
    fi
done
# Run the installed copy, not the one built above, and from somewhere with no
# checkout in sight: a binary that only works inside its own source tree is not
# installed, it is merely copied.
# Its output is captured rather than piped: `cortado` with no command prints
# usage and exits 2, and under `pipefail` that status would sink the pipeline
# however well the text matched.
(cd "$tmp" && "$installed/cortado" >"$tmp/installed-usage.txt" 2>&1) || true
if ! grep -q '^usage: cortado' "$tmp/installed-usage.txt"; then
    echo "FAIL install: the installed cortado does not run" >&2
    cat "$tmp/installed-usage.txt" >&2
    exit 1
fi
pass
echo "ok install: tools/install.sh installs a cortado that runs outside the tree"

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
        # A screen laid out by coordinate rather than by a run, with a shader
        # under it. The tree is the assertion: where a <Box> put each control.
        "$BEANSC" build "$root/examples/gradients/main.b" -o "$tmp/gradients.bin" >/dev/null
        "$tmp/gradients.bin" --dump >"$tmp/gradients.out" 2>&1
        diff -u "$root/tests/gradients.out" "$tmp/gradients.out"
        pass
        # And what the dump cannot see. The toast is in the tree whether or not
        # its buttons work, and for a while they did not: the handlers set the
        # field and never asked for a render.
        "$tmp/gradients.bin" --dismiss >"$tmp/gradients_dismiss.out" 2>&1
        diff -u "$root/tests/gradients_dismiss.out" "$tmp/gradients_dismiss.out"
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

        # ---- the bundled leg, and the only place the gated four can be seen
        #
        # `tests/gated.b` runs on every ordinary leg and proves the half that
        # matters most: every privacy-gated call refuses from a process with no
        # bundle, and the program is still alive afterwards. It has to run
        # there, because *not being bundled* is exactly the state it is testing.
        #
        # This is the other half, and there is no other way to get it. A
        # program with no bundle has no privacy identity: TCC answers for
        # whichever process is responsible for it, so a binary run from a
        # terminal reads the terminal's grants and reporting those as its own
        # would be worse than reporting nothing. Only a real application
        # bundle, with the usage descriptions in its Info.plist, gets a real
        # answer — and this leg builds one, signs it, runs it and reads what it
        # said.
        #
        # `open -W --stdout` rather than running the executable inside the
        # bundle: a bundle is only a bundle to macOS when Launch Services opens
        # it. Run the binary by its path and `[NSBundle mainBundle]` answers a
        # nil identifier, every line reads as it does on an ordinary leg, and
        # the leg would pass while proving nothing.
        #
        # Nothing in tests/bundled.b starts a service, and that is deliberate:
        # touching CoreLocation or CoreBluetooth for real puts a panel on the
        # screen and waits, which on a machine with nobody sitting at it is a
        # hang with no output. Every line there is a status read.
        "$BEANSC" build "$root/tests/bundled.b" -o "$tmp/bundled.bin" >/dev/null
        "$root/tools/bundle.sh" "$tmp/bundled.bin" CortadoGated org.beans-lang.cortado.gated "" \
            NSBluetoothAlwaysUsageDescription="to show what cortado's Bluetooth service answers" \
            NSLocationWhenInUseUsageDescription="to show what cortado's location service answers" \
            NSCameraUsageDescription="to show what cortado's capture service answers" \
            NSMicrophoneUsageDescription="to show what cortado's capture service answers" \
            NSPhotoLibraryUsageDescription="to show what cortado's permission model answers" \
            NSMotionUsageDescription="to show what cortado's permission model answers" \
            >"$tmp/bundled.log" 2>&1 || {
            echo "FAIL bundled:" >&2; cat "$tmp/bundled.log" >&2; exit 1
        }
        plutil -lint "$tmp/CortadoGated.app/Contents/Info.plist" >/dev/null
        codesign --verify --strict "$tmp/CortadoGated.app"
        open -W --stdout "$tmp/bundled.out" "$tmp/CortadoGated.app"
        diff -u "$root/tests/bundled.out" "$tmp/bundled.out"
        pass
        echo "ok bundled: the gated four answer for real from inside a signed .app"
    else
        skip markup_mount "barista is not checked out at ../barista, so the markup example cannot be built"
    fi
elif [[ $native -eq 1 ]]; then
    echo "-- native leg not run: no host for $host_os"
else
    echo "-- native leg not requested (pass --native)"
fi

# ------------------------------------------------------------------ sanitizers
#
# Slow, and not part of the default run. `BEANS_SANITIZE` instruments the Beans
# half, which the compiler's own gate already covers; what this adds is the
# host — fifteen hundred lines of Objective-C with manual retain and release, a
# handle table indexed by arithmetic, and a string boundary that copies bytes
# both ways. `csrc` does not pass sanitizer flags to a manifest's C sources, so
# `tools/sanitize.sh` compiles the host itself with them and links by hand.
if [[ $sanitize -eq 1 && $have_host -eq 1 ]]; then
    # The same list the rest of the run used, not a second copy: a case added
    # above has to reach the sanitizers too, and a hard-coded list here silently
    # stopped covering four of them.
    "$root/tools/sanitize.sh" "${cases[@]}"
    pass
elif [[ $sanitize -eq 1 ]]; then
    skip sanitize "the only host written is macOS"
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
