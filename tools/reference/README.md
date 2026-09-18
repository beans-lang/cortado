# The native reference

Everything in `render/theme.b` is a number read off this Mac. This directory is
how it was read, and — just as important — it is the list of the few things that
could **not** be read, so nobody has to guess later whether a value was measured
or invented.

Native code is allowed here and nowhere else in cortado. None of it ships.

## The pinned machine

```
product   macOS 26.5.0
build     25F71
accent    multicolor, which resolves to controlAccentColor 007affff in both appearances
scale     2.0
reduce motion / transparency / contrast   all off
scrollers overlay
```

`build/reference/pinned.json` is written by every capture run and is the record
of what the numbers describe. A theme value measured on one macOS release is not
evidence about another one; if this file changes, the measurements are stale.

## Running it

```sh
bash tools/reference/capture.sh build/reference     # AppKit stills, ~4 minutes
python3 tools/reference/measure_shots.py build/reference
python3 tools/reference/measure_parts.py build/reference
bash tools/reference/motion.sh build/motion         # recorded clicks, ~15 seconds
```

`capture.sh` builds an **app bundle**. A bare binary never becomes the key
application, and without a key window the default button, the focus ring, the
switch fill and every active tint are wrong — the capture exits non-zero rather
than write shots it cannot vouch for.

Captures are written in **sRGB**. Apple's generic RGB is gamma 1.8, so a capture
taken in it reports every colour several steps off what the renderer emits.

### Comparing cortado against it

```sh
./build/cortado-bx build templates
beansc build examples/reference/main.b -o build/reference-shots
bash tools/reference/run.sh 2          # plan, render, compare at 2x
python3 tools/reference/rank.py        # the table, worst first
```

`run.sh` writes `build/compare/`: `cortado/` (our render of the same boards),
`side/`, `overlay/` (50%), `diff/`, and `report.json`. Comparison is per control
region grown by the focus ring's reach, never the whole board — a large matching
background must not hide a wrong border.

## Where a number comes from

| what | read from |
|---|---|
| frame sizes, baselines, title and drawing rects | `NSControl`/`NSCell` directly, at all four control sizes |
| fonts, ascent, descent, line height, tracking | CoreText on the real UI font |
| system colours | `NSColor` in each appearance, converted to sRGB |
| corner radii, glyph geometry, insets | the **4x** shots, which resolve a quarter point |
| flat fills, rules, borders | an interior pixel of the **2x** shots |
| menu row height, chrome, width rules | `NSMenu.size`, differenced |
| animation duration and curve | `motion.sh`, sampling the presentation tree after a synthesized click |

**Colours are not read from the 4x shots.** A 4x capture blends its own edges,
so the most common colour inside a small shape can be one that is nowhere on
screen. Reading the level indicator's green off a 4x shot gave `33c458` for a
control that paints `34c759`, and every filled pixel then counted as wrong.

**Motion is recorded from a real click.** AppKit only animates a control a
person operated: `switch.state = .on` jumps.

**The motion recorder is not yet trustworthy, and its numbers are withdrawn.**
Three versions of `snapshot` were wrong in three different ways, each of which
produced a plausible-looking recording:

1. `layer.presentation()?.render(in:)` renders a grey approximation of the
   tree. These controls are not layer backed, so none of their own drawing is
   in it — the recording said a switch moved and nothing about its colour.
2. `cacheDisplay(in:to:)` draws the control, but not in a named appearance, so
   the accent came back grey.
3. The window never became key, and an inactive control drains its accent
   anyway — the same trap the still capture solved with one persistent key
   window in a bundle.

The current version uses the still capture's path (`displayIgnoringOpacity`
into an sRGB context under an explicit appearance) and still catches the switch
mid-press. Until a recording shows a control's real colours moving through
intermediate positions, **no duration here is measured**, including the
switch's 0.15s: treat every motion token in `render/theme.b` as unverified and
read its own doc comment for where the number came from.

## What could not be measured

These are the only values in `render/theme.b` that are not read off this Mac.
Each one says so in its own doc comment too.

1. **A menu's painted appearance.** In macOS 26 a menu window is drawn outside
   the application process: it never appears in `NSApp.windows`, and
   `popUp(positioning:at:in:)` and `popUpContextMenu(_:with:for:)` both return
   without one being capturable. So the menu's *layout* is measured — 24 point
   rows, 5 points of chrome above and below, an 11 point separator, a width of
   the widest title plus 32 and 8 more once any item carries a mark, a 12 point
   indent step — while these are not:
   - the **translucent material** behind it. Cortado paints an opaque
     `controlBackgroundColor` sheet. An `NSVisualEffectView` rendered offscreen
     answers its fallback grey, not the blend, so there is nothing to copy.
   - the sheet's **corner radius** (10) and its **shadow**.
   - the **highlight's** inset (5) and radius (4).
   - the split of the 32 points between the leading margin and the trailing
     one. The mark column is measured (8), and the mark's own advance and ink
     come from `CTLineGetImageBounds` on the menu font's check glyph, which puts
     the title at 21 — consistent with the measured width, but chosen rather
     than observed.

2. **The focus ring.** The still capture draws it with the documented
   `NSFocusRingPlacement.only` + `drawFocusRingMask()` pair, and what comes out
   is not a ring: on a focused push button it reaches 1.5 points past the
   control on the **right only**, and nothing above, below or left. A ring is
   symmetric, so the capture is wrong rather than AppKit. The `focused` rows in
   any comparison are therefore measured against a reference that is not
   trustworthy, and cortado's own ring is built from the measured colour
   (`keyboardFocusIndicatorColor` at half alpha, which matches the capture's
   `80b3fa` over white exactly) rather than from that geometry. Until the
   capture is fixed, treat `focused` as unverified — it is the largest single
   row in the residual table for that reason.

3. **A tab view's bezel.** `NSTabView` is not in the shot set; its row is drawn
   as the segmented control AppKit uses there, which *is* measured.

4. **Windows and Linux.** Every number here is macOS 26.5. The same shared
   drawing runs on all three platforms, but the UI font does not: see
   `RENDERING.md` for what that costs and what would fix it.
