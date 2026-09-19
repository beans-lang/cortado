# Shared rendering migration

The shared backend is experimental. The native backend remains the default.
This change builds the foundation, shared controls, and desktop adapters. It
does **not** complete the six-stage migration or its desktop acceptance gate.

## What runs

The `.bx` demo uses this path:

```
.bx -> generated Beans Component -> existing Mount / Differ / layout Solver
    -> Beans Widget / RenderObject -> DisplayList -> Skia -> one native Canvas
```

- `paint/` defines typed renderer, paragraph, canvas, and drawing-command classes.
- `render/` owns the retained tree, validated properties, generation-checked
  handles, focus, pointer capture, text editing, scroll offsets, theme values,
  separate invalidation revisions, and basic semantics snapshots.
- `component/ControlTemplate` and `TemplateSet` mount `.bx` visual trees separately
  from their controls. Templates cannot take the owning control's keyboard
  behavior or semantics identity. Closing a scene removes mounts and callbacks,
  invalidates handles, and releases the graphics engine.
- `templates/*.bx` supplies buttons, text fields, toggles, ranges, separators,
  group boxes, disclosure, choices, tabs, split panes, and popup chrome. Generated Beans is
  checked in and checked for drift. `coffee_button.bx` shows an app replacing a
  button template using ordinary markup.
- `skia/` is an optional Beans module. Its C++ bridge owns graphics resources,
  paragraph shaping, UTF-8 position conversion, grapheme boundaries, software
  surfaces, and GPU surfaces. No C++ widget behavior or layout is added.
- `cortado_skia.Window` presents one raster image through a native Canvas, forwards
  pointer/key input, and follows window size and scale. The app assigns each
  window a separate handle namespace. Standalone `Scene` callers supply distinct
  namespace numbers when they use more than one scene.

Shared widget construction supports `Container`, `Label`, `Button`, `TextField`,
`SecureField`, `SearchField`, `TextArea`, `ScrollView`, `CheckBox`, `RadioButton`,
`Switch`, `Slider`, `Stepper`, `ProgressBar`, `LevelIndicator`, `Separator`,
`GroupBox`, `Disclosure`, `ComboBox`, `Segmented`, `TabView`, `SplitView`, and
`Table` cells. Tables accept typed `columns`, `column_widths`, `source`, and
`editable_when` expressions in `.bx`; their templates ask for viewport cells plus
overscan, rather than reading the entire source. Selection and scrolling stay in
Beans. A stable `component.TableEditRule` supplies the edit policy. Idle cells are
`.bx` labels. Double-click or Return opens one text field; Return raises `on:commit`
on the table with row, column, and proposed text. Escape cancels. Arrow keys select
rows and columns. The source remains authoritative. Unrelated component updates
preserve the active draft; selecting another row or scrolling the editor fully out
of view cancels it. Disposal clears the source and edit callback.

The table caches visible cell values until the source is refreshed, reading only
new rows as they enter the viewport. Fractional scrolling reuses those values.
Window wheel events wait in a bounded queue until the next frame and keep their
original order, with pending input applied before hit testing. Window presentation uses independent snapshots. A persistent readback buffer
was slower in the native timing test, so it is not used for window presentation. Skia still paints and copies a whole frame, so these
changes do not guarantee a frame deadline on every machine.

Eight existing widget kinds still lack a shared construction path: `ImageView`,
`Canvas`, `Spinner`, `Link`, `DatePicker`, `ColorWell`, `WebView`, and `OutlineView`.
Declarative drawing primitives already provide a portable drawing path; this does
not make arbitrary raw Canvas shaders portable. Web views need native composition.
Shared drawing includes `Rectangle`, `Ellipse`, SVG `Path`, and local
`ResourceImage` files, with vertical gradients, shadows, clipping, and transforms.
Drawing properties can use `transition_seconds` and `transition_easing` to
interpolate typed values in Beans. Initial values do not animate; later changes
can come from `.bx` state expressions. `Scene.advance(seconds)` supplies a
deterministic test clock. A shared window subscribes to native frames only while
its animation queue contains work, and stops the clock when it becomes idle.
Control templates receive `hovered`, `pressed`, `focused`, and `enabled` state.
The custom coffee button demonstrates an animated hover fill entirely in `.bx`.
Existing
`VStack`, `HStack`, `Grid`, and `Box` markup
uses the same containers and layout solver. Unsupported controls and properties
return errors; they do not quietly create native widgets inside a shared scene.

Text editing uses Skia paragraph geometry for drawing, hit testing, selection,
and caret placement. Beans owns grapheme-safe edits, selection, undo/redo, and
composition state. Text-field `bind:value` keeps its existing **commit** behavior.
The desktop adapters forward input-method events, clipboard, and wheel input.
The macOS adapter supplies virtual accessibility elements and a native text-input
client. Windows exposes a virtual UI Automation tree with invoke, toggle, and
selection actions. GTK4 exposes virtual accessible widgets and actions through
its AT-SPI bridge. Focused Mac and GTK-on-mac native tests and Windows tests
under Wine pass with `tools/test_accessibility.sh`; these check event delivery,
roles, actions, stale nodes, and teardown. Real IME sessions and VoiceOver,
NVDA, and Orca use still need acceptance testing on their target desktops.
The `.bx` `a11y_label` attribute supplies a control's accessible name. Its
bindings and removal use the same differ as other properties. Windows value,
range, and text patterns and a parent-child semantics tree are still pending. Cursor
movement is logical; full visual movement through bidirectional text is pending.

The engine supports Skia Ganesh Metal on macOS, Vulkan on Windows, and EGL OpenGL
on Linux. GPU drawing currently reads pixels back into the native Canvas; this is
not a zero-copy presenter. Metal selection, pixels, and software recovery have
passed local tests. The pinned Linux SDK builds with GCC in Debian bookworm and
runs the Skia OpenGL path through Mesa llvmpipe with surfaceless EGL. That test
checks pixels and software recovery; it does not prove hardware GPU output or
GTK presentation under Wayland/X11. Windows Vulkan still needs native build and
run verification. The software backend stays the default for repeatable tests.

## Build and run

Use a built Beans compiler on PATH, Python 3.11+, CMake 3.20+, and the native C/C++
toolchain. Linux also needs GTK4 and Fontconfig development packages. Windows
needs the toolchain matching the pinned Skia archive. Windows Skia engine builds
still need verification on that system.

From the Cortado directory:

```sh
python3 tools/prepare_skia.py
beansc build examples/cortado_bx.b -o build/cortado-bx
build/cortado-bx build templates
build/cortado-bx build examples/rendered/site
beansc build examples/rendered/main.b -o build/rendered
build/rendered --window
```

`build/rendered --snapshot` writes `build/rendered.png` without creating a native
application. `build/rendered --window-smoke` runs a bounded desktop presentation,
input, multiple-window, and teardown check. The module also works with
`beansc run examples/rendered/main.b`.

`--window` opens the `.bx` gallery, with navigation to the demo, controls,
graphics-backend selection, editing, choices and panes, a 10,000-row editable table, custom composition,
theme changes, drawing and motion, and accessibility pages. `--gallery-snapshot` writes a PNG
for each page. New controls belong in these pages and in the shared test gate.

An app opts in at build time by requiring the `skia` module and using its `Scene`
or `Window` as its composition root. Existing app commands and native constructors
keep their behavior. A general CLI backend switch has not been added.

`skia/dependencies.json` pins six desktop SDK assets and their SHA-256 hashes.
`prepare_skia.py` verifies the archive before extraction and builds the engine.
`--archive PATH` accepts an already downloaded archive; `--fetch-only --target
linux-x64` fetches a cross-target SDK without pretending to build it locally.

The interpreter and native program load the same engine library. In this checkout,
the loader finds it under `build/skia/lib/`. Packaged apps must currently bundle the
engine and set `CORTADO_SKIA_LIBRARY` to its absolute path before creating a renderer.
Automatic bundling, distribution notices, and release packaging remain pending.
A shared library is loaded once; set that environment variable before first use.

The presentation bridge accepts opaque RGBA frames. Translucent shapes must be
composited into the frame first. Transparent desktop windows are not supported.
### The font, and what it costs off macOS

The macOS theme is measured against the system UI font. On macOS the engine asks
CoreText for it per point size, so a 9 point control gets the optical cut AppKit
gives a 9 point control, and registers that face under a name of its own — the
shaper resolves a face by family, and a typeface left unnamed comes back as a
different optical cut with narrower glyphs and a taller line.

**Windows and Linux do not have that font.** The engine names Segoe UI Variable
Text and then Inter, Cantarell, Noto Sans, DejaVu Sans. Those are different
typefaces: the same string is a different width, so a control measured from its
title is a different size, and the geometry this theme pins does not follow.

`Renderer.use_font(path)` makes one font file the family every later paragraph
uses, on every platform, which is the mechanism that would close the gap. It is
not wired to an asset, because SF Pro's licence covers use on Apple platforms
and does not cover redistributing it inside an application for Windows or Linux.
Closing this honestly means bundling a metric-compatible, freely redistributable
face and re-measuring the theme against **that** on all three platforms.

Until then: **the same shared drawing runs everywhere and the same layout
arithmetic runs everywhere, but pixel equality with the pinned macOS reference
is claimed on macOS only.**

## Checks

```sh
python3 tools/test_rendered.py --sanitize
tools/test_accessibility.sh
tools/test_skia_linux.sh
CORTADO_ALLOW_SKIP=ios_run ./test.sh --case raster --native
./test.sh --case render --native
```

Only name `ios_run` as an allowed skip when no simulator is available. The shared
gate checks generated bindings/templates, actual Skia pixels and shaped text,
Unicode editing, stale handles and tree ownership, `.bx` commit bindings and
component identity, custom templates, scaling, scrolling, idle redraw, and cleanup.
It runs both interpreted and native Beans. Sanitizer mode also checks native
Beans, the host bridge, and a separately built C++ graphics bridge. The prebuilt
Skia archives themselves are not sanitizer builds.

The raster test checks presentation-buffer validation on the desktop hosts. The
window smoke test compares a native canvas pixel with the Skia frame where native
snapshot support exists. GTK4 on macOS and Win32 under Wine can test their host
adapters; they do not prove Wayland, X11, or a native Windows Skia engine works.

## Work still required before switching the default

1. Verify the desktop adapters on real macOS, Windows, and Linux: frame scheduling,
   gestures, clipboard, IME sessions and candidate positioning, and accessibility
   with VoiceOver, NVDA, and Orca. Adapter unit tests do not replace these checks.
2. Verify Vulkan and OpenGL on real desktop hosts, exercise actual device loss,
   and add direct OS-surface presenters to replace GPU pixel readback.
3. Extend the shared vocabulary model and `.bx` compiler with resource and theme
   declarations, named states, and animation timelines beyond drawing-property
   transitions.
   Text-field content/selection/caret still need declarative presenters. New visual
   features must include editor metadata, source diagnostics, an example, and tests.
4. Migrate the remaining controls, pickers, outlines, and
   customizable collection templates.
   Ordinary scrolling currently lays out its full content.
5. Add markup descriptions for system menus/dialogs and explicit web-view
   composition rules. Native web views and raw GPU APIs are unchanged.
6. Run the full `.bx` gallery and existing app acceptance suite on all desktops,
   with pinned-font snapshots, GPU output, IME/accessibility checks, display scale,
   device recovery, and Wayland/X11. Then add the default-backend switch and remove
   duplicate native desktop controls. Keep iOS native until its own migration.

No stage is complete merely because its interfaces or placeholders exist.
