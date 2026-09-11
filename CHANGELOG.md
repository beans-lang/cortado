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

### Not done yet, on purpose

- `Application.shutdown` unregisters the platform callback but does not
  `close()` it. Closing wants a named local, and Beans refuses `move self.sink`
  because moving out of a field would leave the object half-built. Unregistering
  is the half that matters — afterwards the platform holds no pointer into
  Beans, which is the property `close` exists to guarantee. One closure per
  process is left for exit to reclaim. Owning the callback as a local inside
  `run()` would close cleanly and break the headless case, where a test builds
  and measures a whole tree and never starts an event loop.
