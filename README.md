# cortado

Native desktop applications, written in Beans.

A cortado `Button` is a real `NSButton` on macOS, a real `BUTTON` window class
on Windows, a real `GtkButton` on Linux. Nothing is drawn to imitate a control.
That one decision is where everything else follows from: the application
inherits the platform's own text input, input methods, dictation,
spell-checking, accessibility tree, keyboard conventions, selection behaviour
and dark mode, instead of reimplementing them and getting them subtly wrong in
every language but English.

```beans
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.geometry
import cortado.events
import std.io

fn run() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.gui)
    var window: surface.Window = app.window(420.0, 230.0, "Cortado")?

    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?

    var order: widgets.Button = widgets.Button.of("Order")?
    order.set_frame(geometry.Rect.of(24.0, 24.0, 110.0, 32.0))?
    root.add(order)?

    app.router.on(order.handle(), events.EventKind.activate,
        fn(event: events.UiEvent) { io.println("ordered") })

    window.show()?
    app.run()
    return ok(true)
}
```

```
beansc build examples/hello.b -o build/hello && ./build/hello
```

## Status

macOS works. Windows, Linux, iOS and Android are designed for and not yet
built — the flat C ABI in `src/cortado_host.h` is what they plug into, and the
Beans half already type-checks for all of them (`test.sh` proves it on every
run).

| | |
|---|---|
| macOS | AppKit. Window, container, label, button, text field, check box, image view, events, measurement |
| Windows | designed, not written. The layout engine already runs and is tested here |
| Linux | designed, not written. The layout engine already runs and is tested here |
| iOS, Android | designed, not written. Beans has no target triple for either yet |

## How it is put together

```
your program
     │
cortado.component   the retained tree .bx markup renders into        (not yet)
cortado.surface     windows, and the application that owns them
cortado.widgets     the controls
cortado.layout      where everything goes — arithmetic, no controls
cortado.events      what the user did
cortado.platform    what this platform can and cannot do
cortado.geometry    points, sizes, rectangles
cortado.host        the flat C ABI, and the only package that names it
     │
src/cortado_host.h  ── src/cortado_macos.m   (+ win32, gtk4, uikit, android)
```

Five rules hold the boundary, and each one is enforced by something that can
fail rather than by a comment:

**Nothing platform-specific reaches Beans.** `objc_msgSend`, COM and GObject
stop inside `src/`. `tools/check_abi.sh` greps for them in every `.b` file
outside `cortado.host` and fails the build if one appears. This is not only
tidiness: Beans cannot call `objc_msgSend` at all, because arm64 requires it
cast to each call's signature and there is no way to spell that from Beans.

**No struct crosses the ABI by value.** Geometry travels as loose doubles and
comes back through a caller-owned buffer. Beans can pass structs by value, but
no `extern "C" struct` of `f64` exists anywhere in the compiler's test suite —
the `CGRect` shape is the one ABI classification nothing has exercised, and a
UI framework whose every call is geometry is the wrong place to find out.

**A handle is an integer, not a pointer.** The high half is a generation
counter; releasing a widget bumps it, so a handle held past its widget's life
answers `stale` instead of reaching freed memory. A dangling `NSView *` looks
exactly like a live one until it crashes, and raw pointers copy freely, so
freeing through one alias leaves every other alias dangling with nothing able
to tell.

**Text is UTF-8 with an explicit length, never NUL-terminated**, and is copied
at the boundary. A string with an embedded NUL crosses whole.

**Coordinates are top-left, y downward.** Windows, GTK4, UIKit and Android
already agree; the macOS host flips, so nothing above `cortado.host` ever sees
AppKit's bottom-left convention.

## Layout

You describe the design; the solver produces the frames. Nothing below names a
coordinate:

```beans
var sheet: widgets.WidgetLayout = new widgets.WidgetLayout()

var body: layout.StackLayout = layout.StackLayout.column(12.0)
body.set_padding(geometry.EdgeInsets.all(24.0))
body.set_align(geometry.Align.stretch)

var page: layout.LayoutNode = sheet.group("page", container, body)
page.add(sheet.leaf("heading", heading))
page.add(sheet.leaf("drink", drink))

var bar: layout.StackLayout = layout.StackLayout.row(12.0)
bar.set_justify(layout.Justify.end)
var buttons: layout.LayoutNode = sheet.spacer("buttons", bar)
buttons.add(sheet.leaf("order", order_button))
buttons.add(sheet.leaf("quit", quit_button))
page.add(buttons)

var solver: layout.Solver = new layout.Solver(sheet)
solver.solve(page, geometry.Rect.at(geometry.Point.zero(), window.content_size()?))?
sheet.apply(page)?
```

Four algorithms, each its own class: `StackLayout` (a row or a column),
`FlexLayout` (the same, with children sharing out the space that is left over),
`GridLayout` (tracks that are fixed, automatic or a fraction of what remains),
and `AbsoluteLayout` (the escape hatch). Every one takes padding, spacing,
main-axis justification and cross-axis alignment, and every child may carry a
margin, size bounds, a grow and shrink weight, and an alignment of its own.

Three decisions are worth knowing about, because each is a class of bug the
engine does not have:

**The engine never touches a platform.** It asks an integer key how big it
wants to be, through one injected interface with one method
(`layout.Measure`). `TableMeasure` answers from a table, so all 69 layout
goldens run with no display, no window server and no foreign call — on Linux,
on Windows, under the tree interpreter and as a native binary. A frame that
comes out wrong is a solver bug and can be nothing else. `WidgetLayout` is the
other implementation: it asks the real control.

**Right-to-left is one pass, not a parameter.** Every algorithm lays out left
to right, and the solver mirrors the finished frames once — about each
container's *content* box, so asymmetric padding stays where the designer put
it. Threading a direction flag through four algorithms would mean testing all
four twice; here there is one ten-line function and one test that checks the
reflection is exact.

**Frames snap to device pixels on shared edges.** Rounding a position and a
size independently is how a row of boxes ends up with a one-pixel gap: two
neighbours at x=10.5 and x=20.5 both round their positions down and their
widths down, and the second starts a pixel after the first ends. cortado rounds
the absolute left and right edges instead, so the right edge of one box and the
left edge of the next are the same number and always meet. It is absolute
because a parent rounded by half a pixel would otherwise shift every descendant
by that half pixel.

## Building

```
./test.sh              # the interpreter leg, the gates, cross-target checks
./test.sh --native     # also build and run every case as a real binary
```

`test.sh` finds the compiler as `$BEANSC`, then `$BEANS_ROOT/build/beansc`,
then `../../beans/build/beansc`, then `PATH`.

After editing `src/cortado_host.h`:

```
./tools/regen_sys.sh   # regenerate host/sys.b, then run both boundary gates
```

## How it is tested

A native control has no output to compare. It does have a shape, a class name,
an accessibility role, a frame and a state — and every one of those is an
answer only the real platform object can give. So the suite builds a widget
tree and prints it:

```
Container CortadoView role=group "" frame=0,0,480,320 children=5
  Label NSTextField role=text "Order a coffee" frame=20,20,240,20
  TextField NSTextField role=textbox "flat white" frame=20,52,200,24
  CheckBox NSButton role=checkbox "Extra shot" frame=20,88,200,20
  ImageView NSImageView role=image "" frame=300,20,64,64
  Container CortadoView role=group "" frame=20,130,300,40 children=2
    Button NSButton role=button "Order" frame=0,0,100,32
    Button NSButton role=button "Cancel" frame=110,0,100,32 disabled
```

Four things about that are deliberate.

**The dump is written in Beans, not in the host.** If the host formatted it,
the tree interpreter and a native build would call the same compiled function
and print identical bytes even with the whole foreign-function layer broken —
the comparison would prove nothing. Written in Beans, matching output means
both backends classified every signature, read every out-pointer and
marshalled every string the same way.

**`children=` is read back from the platform**, not from cortado's own list,
and the two are compared on every line. Bookkeeping that is never checked
against the thing it describes is how a tree ends up correct on paper and
wrong on screen. This check found a real divergence the first time it ran: an
`NSImageView` carries a private subview of AppKit's own, so the host now counts
only the views cortado put there.

**Everything runs headless.** Under `AppRole.headless` a surface is built,
sized and measured by the platform's real text metrics, and never ordered
front — so a continuous-integration runner reads the same tree as a desk.
`tests/headless.b` is the negative control: it requires that a headless
surface reports itself invisible *and* that a non-headless one does not,
because a probe that always answered "yes, headless" would be
indistinguishable from one that worked.

**Skips are counted and must be declared.** A gate that quietly skips a leg
when its input is missing reads green forever once the layout moves under it.
`test.sh` counts every skip, names it, and fails unless it is listed in
`CORTADO_ALLOW_SKIP` — so the decision to skip lives in the workflow file
where someone can see it.

The layout suite is checked differently, because a table of frames proves the
numbers have not changed without ever proving they were right. `tests/layout.b`
ends with five verdicts computed from the frames rather than copied out of
them: that snapped neighbours share an edge exactly, that every frame lands on
the pixel grid at scale 1 and at scale 2, that a right-to-left layout is the
exact reflection of the left-to-right one about the content box, and that
`fit` agrees with what a solve needs. Each was checked by breaking the thing it
guards and watching it turn red.

`tests/bridge.b` covers the seam between the two. It lays out real AppKit
controls through the engine and then reads the frames back off the platform,
so it fails if `apply` writes nothing, writes to the wrong control, or gets an
offset wrong. It also asserts that three different kinds of control measured to
three different heights — a "height greater than zero" check reads green
through a hard-coded constant, and this one does not.

## License

MIT.
