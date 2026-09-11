# Changelog

## Unreleased

First working macOS host.

- `cortado.host` — the flat C ABI (`src/cortado_host.h`, 40 entry points) and
  its generated Beans binding. Handles carry a generation, so a handle used
  after its widget is released is a checked error rather than a jump into freed
  memory. No struct crosses by value; text is UTF-8 with an explicit length and
  is copied at the boundary.
- `cortado.geometry`, `cortado.platform`, `cortado.events`, `cortado.widgets`,
  `cortado.surface` — points and rectangles, capability queries, the event
  router, `Container` / `Label` / `Button` / `TextField` / `CheckBox` /
  `ImageView`, and `Window`.
- `src/cortado_macos.m` — the AppKit host. Coordinates are top-left with y
  downward everywhere in cortado, which the four other target platforms already
  use; this file is where the flip happens, in a `CortadoView` that answers YES
  to `-isFlipped`.
- One platform callback for the whole process, not one per widget. A stored
  callback holds a strong reference its cycle collector cannot trace, so a
  per-widget closure capturing its own widget would leak with nothing able to
  reclaim it. Handlers live in `EventRouter` as ordinary functions instead.
- `tools/check_abi.sh` and `tools/check_constants.sh` — the two gates that hold
  the header, the binding and the hand-copied constants to each other, and that
  fail the build if a platform symbol appears in a `.b` file outside
  `cortado.host`.

- `cortado.layout` — the layout engine, in pure Beans with no foreign call in
  it at all. `StackLayout` (a row or a column), `FlexLayout` (the same, sharing
  out leftover space), `GridLayout` (fixed, automatic and fractional tracks)
  and `AbsoluteLayout` (explicit coordinates), over a `LayoutNode` tree that
  holds no handles. Padding, spacing, margins, size bounds, main-axis
  justification, cross-axis alignment including stretch, right-to-left
  mirroring and device-pixel snapping.
- The one thing the engine cannot compute — how wide a label renders — is
  injected as `layout.Measure`, a single-method interface. `TableMeasure`
  answers from a table, which is what lets all 69 layout goldens run on a
  machine with no window server: `test.sh` runs them on every platform and
  under both backends, so a layout bug is found by a Linux runner and not only
  by a Mac.
- `widgets.WidgetLayout` is the other implementation of that interface. It
  hands out the keys, measures through the real control, and writes the solved
  frames back. Everything that touches a platform lives in that one file.
- `FlexLayout.distribute` is a freeze loop, not one division. A child that hits
  its own minimum or maximum stops absorbing its share, and the space it
  refuses has to go to the others — dividing once and clamping afterwards looks
  right on a two-child example and silently leaves 300 points of room holding
  280 points of children.
- Frames snap on absolute shared edges rather than on positions and sizes
  independently, so neighbouring boxes always meet and a parent rounded by half
  a pixel does not shift its descendants.

### Found while building this

- An `NSImageView` carries a private subview of AppKit's own. The tree dump
  compares cortado's child list against the platform's on every line, which
  caught it the first time it ran; the host now counts only the views cortado
  tagged, so a query answers about the program's tree rather than about
  AppKit's internals.
- Asking a plain container whether it is enabled used to answer "no", which
  reads as *disabled* rather than as *has no such property*. It answers
  `wrong_widget` now, and `describe()` prints the flag only for widgets that
  actually carry one.
- A control grouped by a layout-only node landed at the top of the window
  instead of on its row. The layout tree and the control tree deliberately have
  different shapes — `WidgetLayout.spacer` groups widgets without creating a
  native view for them — and `apply` was writing each node's frame straight
  onto its control without adding the origin of the layout-only nodes in
  between. It was found by running `examples/hello.b` and looking at it: every
  golden passed, because none of them had such a node. `tests/bridge.b` has one
  now, and reverting the fix turns two of its lines red.

### Not done yet, on purpose

- `Application.shutdown` unregisters the platform callback but does not
  `close()` it. Closing wants a named local, and Beans refuses `move self.sink`
  because moving out of a field would leave the object half-built. Unregistering
  is the half that matters — afterwards the platform holds no pointer into
  Beans, which is the property `close` exists to guarantee. One closure per
  process is left for exit to reclaim. Owning the callback as a local inside
  `run()` would close cleanly and break the headless case, where a test builds
  and measures a whole tree and never starts an event loop.
