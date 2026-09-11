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

- `cortado.component` — components, and the reconciler behind them. A render
  produces a tree of `Element` values and touches no control; `Differ` compares
  it with the previous tree and `Applier` turns the difference into platform
  calls. `Component` carries the lifecycle (`on_init`, `on_params_set`,
  `on_mount`, `on_unmount`, `should_render`), `Builder` is the method ABI `.bx`
  will emit against, and `Mount` owns a live tree and re-renders it.
- `cortado.annotations` — `@view`, `@param`, `@inject`, `@window`, `@command`
  and `@platform`, every one `@retention(value: "runtime")` because the default
  is not runtime and a scan that cannot see an annotation is not a scan.
- `cortado_app` — a sibling module holding the barista bridge. It is separate
  because a package under a module may not import its own module root, so the
  composition root cannot live inside cortado; and because keeping it out means
  cortado's core has no dependency on any container at all.
- Keyed reconciliation. A child with a `key` keeps its control across
  reordering, insertion and filtering; children without one match by position.
  Reversing three keyed rows emits two moves, and `tests/diff.b` records the
  unkeyed cost beside the keyed one so the difference is visible rather than
  claimed.
- `EventRouter.after` — one callback, run after a batch of events drains rather
  than after each event, so a handler that triggers three more causes one
  render and not four.
- `Widget.set_display_text`, `set_property` and `set_property_real` — generic
  access by host property id, for the applier. Application code keeps the named
  methods, which say what they do.

- `cortado.bx` — the `.bx` markup compiler, and `cortado-bx`, its command line.
  A screen is one file: markup on top, a `<beans>` block underneath, one
  `partial class`. Tags name controls (`VStack`, `Button`, `Label`) and any
  other capitalised tag is a component; there is no `<div>`, no entity table,
  no escaping and no `$html`, because the output is a tree of native objects
  and there is nothing to inject into.
- Forked from latte's `bx/`, which was already target-parameterised, and the
  HTML removed: the void-element, raw-text, RCDATA, entity, URL-scheme and
  escaping tables, the inline-handler refusals, and the constant folder with
  its second serializer. What is left — the lexer, the parser, the AST, the
  `<beans>` passthrough and the `partial class` splice — is the part that was
  never about HTML.
- Attributes are **typed**. latte writes every attribute as a string because
  HTML attributes are strings; a control's properties are a number, a flag or
  one word out of a closed set, so the emitted call is typed and
  `spacing={self.name}` is `expected f64, got string` at the author's own
  expression.
- `Builder.child<T>` and `Composer.obtain` — a component named in markup is a
  type, not an object, so the mount builds and owns it. Generic on the concrete
  `Builder` rather than on the `Composer` interface, because Beans refuses
  generic interface methods; the interface answers a boxed `reflect.Value` and
  the downcast happens in the generic method, which is legal precisely because
  a `reflect.Value` is the one source `as?` may narrow to an instantiation.
- `component.Activator` and `Mount.use_activator` — who builds a type named
  only in markup. With a container, its initializer's parameters are resolved;
  without one, the type's own zero-argument initializer is called.
- `tools/check_vocabulary.sh` — holds `bx/widgets.b` against
  `component/vocabulary.b`. Two tables exist because `cortado.bx` must build
  where there is no platform host, and two tables drift.

- Seven more controls: `Slider`, `ProgressBar`, `Separator`, `TextArea`,
  `ComboBox`, `ScrollView` and `RadioButton`. Twelve in all, every one a real
  platform object — `tests/shelf.b` prints each one's native class, which is
  the only answer that proves it.
- Item lists in the ABI (`ctd_items_*`), replaced wholesale rather than
  patched: a list of choices is rebuilt from whatever the program is showing,
  and diffing one would mean a second reconciler for a control whose contents
  are strings. The selection is an index, because two items may read the same.
- **A control now reports the event it actually is.** A button raises
  `activate`; a check box, radio button, slider and combo box raise
  `value_changed`; a text field raises `commit`. AppKit sends all of them down
  one selector, so the host decides from the kind the control was created as.
- `ctd_event` carries `text` (ABI 2): the committed text or the chosen item, at
  the moment the platform raised the event. A handler that had to go and read
  it would need the widget object — the coupling the event exists to avoid —
  and by then the control may have moved on.
- `ctd_widget_synth_value` / `ctd_widget_synth_text`, and
  `Widget.set_value_as_user` / `set_text_as_user`. The ordinary setters change
  a control **silently**, which is right: a program that heard about its own
  writes would feed itself. These are the other half, and they are what a test
  uses — `activate()` on a combo box opens its menu and never returns.
- `widgets.Holder` — the interface a `Container` and a `ScrollView` both
  answer. They are not related by inheritance, because a scroll view is not a
  box with a scrollbar: it puts its children somewhere the platform chose.

- **Menus, with roles.** A command declared with a role is placed, named and
  keyed by the platform: `CommandRole.preferences` comes back as `Settings…` at
  Command-comma on macOS. Cut, Copy, Paste, Undo and Select All get no target,
  so the responder chain finds the focused field — wiring them to a handler
  would break editing in every system control in the window. A command with no
  role is the application's own and raises `command` with its token.
- **Dialogs, asynchronous.** Message, confirm, open and save, each taking a
  token and answering with an event. A dialog always answers: with no visible
  surface to hang from, a message answers its default button and a file dialog
  answers a cancel. A sheet on an unshown window runs no completion handler at
  all, so anything else would leave the caller waiting on a token that never
  arrives.
- `platform.Appearance`, `Surface.scale` and `platform.SystemFont` — light or
  dark, the backing-store scale to hand the layout solver, and the system's own
  font families by role rather than by name.
- `tools/bundle.sh` — a `.app` with an `Info.plist`, ad-hoc signed. The gate
  lints the plist, verifies the signature, launches the bundle and checks the
  running process is named after it, which only holds if Launch Services read
  the plist.

- `tests/roles.out` — the one golden every platform must print. It holds
  cortado's own vocabulary and frames from a layout where every size is a
  constant, and nothing a platform names, so a second host's diff against it is
  the port's definition of done. The gate refuses the file if a platform's
  class name ever appears in it.
- `tools/check_hosts.sh` — holds every host in `src/` to the header. The C
  linker is the real enforcement, but a link only happens where a toolchain
  does; this does the same check on text and runs anywhere.

- **An iOS host.** `src/cortado_uikit.m` implements the same 61 entry points
  over UIKit, and `test.sh` builds `tests/roles.b` for `arm64-apple-ios-sim`,
  runs it in a booted simulator and diffs it against the macOS run. Identical
  bytes. Nothing above the host changed.
- iOS has no menu bar, and that is what `CTD_CAP_MENU_BAR` answering no looks
  like: every menu call is a typed `CTD_ERR_UNSUPPORTED` rather than a silent
  no-op. This is the first host to exercise the capability API, which is the
  reason it exists.

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
- `grow={1}` inside a plain `<HStack>` did nothing and said nothing — the
  silent no-op cortado refuses everywhere else. It was visible the moment the
  gallery ran: a slider that should have filled its row came out zero wide.
  `Builder` now refuses `grow`, `shrink` and `basis` whose parent does not
  flex, and names `<HFlex>` in the message.
- Asking a text area how many children it had answered `stale_handle`. The
  host used one helper for "where do children go" and "where are the children",
  and a text area has an answer to the second (none) and not the first. They
  are two questions now, and a tree walk no longer has to know which kinds to
  skip.
- **A platform control may refuse the frame it is given.** `tests/roles.out`
  used to carry frames, on the theory that a layout built entirely from
  constants must produce identical frames everywhere. It does — and a
  `UISwitch` came back 51 by 31 and a `UIProgressView` 4 points tall anyway,
  because both clamp to their intrinsic size. A frame is therefore not a
  portable fact and has left the portable golden; the solver's arithmetic is
  checked by `tests/layout.out` on every runner, and what each platform did
  with it by `tests/shelf.out`.
- A check box's text had nowhere to go on iOS: a `UISwitch` shows none, because
  the label beside one is a separate view. It becomes the switch's
  accessibility label, which is where that string belongs on that platform and
  what VoiceOver reads.
- The iOS leg skipped silently at first because `beansc --help` exits 2 and
  `set -o pipefail` turned that into "this compiler has no iOS target". The
  skip ledger is what caught it — an undeclared skip fails the run.
- Three container tags — `Grid`, `HFlex`, `VFlex` — compiled in markup and
  were refused by the run-time Builder, so a `<Grid>` would have produced a
  fault at mount rather than a grid. `tools/check_vocabulary.sh` caught it the
  first time it ran, which is the entire argument for writing that gate before
  writing more tags.
- A first render produced controls that looked right and did nothing. The
  differ emits one `create` carrying the whole tree, and no `bind` for anything
  inside it — there was no previous tree to compare against — so the applier
  built the subtree and never subscribed its handlers. Found by a test that
  fires a real `performClick:` rather than by one that checks the tree looks
  right.
- Tearing a mount down left one dead subscription per control below the top
  level, each holding the mount alive. `close` forgot only its direct children.
  The gate asserts the router is empty afterwards, which is what caught it.
- A control grouped by a layout-only node landed at the top of the window
  instead of on its row. The layout tree and the control tree deliberately have
  different shapes — `WidgetLayout.spacer` groups widgets without creating a
  native view for them — and `apply` was writing each node's frame straight
  onto its control without adding the origin of the layout-only nodes in
  between. It was found by running `examples/hello.b` and looking at it: every
  golden passed, because none of them had such a node. `tests/bridge.b` has one
  now, and reverting the fix turns two of its lines red.

### Not done yet, on purpose

- **No Windows or GTK4 host.** Both are bounded work against a header that two
  platforms have now exercised, and `tests/roles.out` is waiting to be the
  proof — the iOS port needed no change above the host at all. But this machine
  has no mingw and no GTK4, so one written here could not be compiled, let
  alone run, and a host nobody has run is not a port.
- **The iOS file dialog answers a cancel.** A document picker reports through a
  delegate rather than a completion block, and wiring one is a piece of work
  that has not been done. It answers rather than hanging, which is the contract
  that matters, and the answer is a refusal the caller can see.
- **Android needs a Beans target first.** There is no `aarch64-linux-android`
  triple. The NDK is on this machine and the work is tractable, but it is
  compiler work and comes before any JNI host.

- `Application.shutdown` unregisters the platform callback but does not
  `close()` it. Closing wants a named local, and Beans refuses `move self.sink`
  because moving out of a field would leave the object half-built. Unregistering
  is the half that matters — afterwards the platform holds no pointer into
  Beans, which is the property `close` exists to guarantee. One closure per
  process is left for exit to reclaim. Owning the callback as a local inside
  `run()` would close cleanly and break the headless case, where a test builds
  and measures a whole tree and never starts an event loop.
