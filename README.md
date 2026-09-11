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
| Windows | designed, not written |
| Linux | designed, not written |
| iOS, Android | designed, not written. Beans has no target triple for either yet |

## How it is put together

```
your program
     │
cortado.component   the retained tree .bx markup renders into        (not yet)
cortado.surface     windows, and the application that owns them
cortado.widgets     the controls
cortado.layout      where everything goes — arithmetic, no controls   (not yet)
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

## License

MIT.
