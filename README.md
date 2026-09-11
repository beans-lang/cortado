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

macOS, iOS and Linux have hosts. Windows and Android are designed for and not
yet built — the flat C ABI in `src/cortado_host.h` is what they plug into, and
the Beans half already type-checks for all of them (`test.sh` proves it on
every run).

| | |
|---|---|
| macOS | AppKit. Twelve controls, events, measurement, layout, components, markup, menus, dialogs, bundling |
| iOS | UIKit. Twelve controls on screen in the Simulator, and the same `tests/roles.out` as macOS |
| Linux | GTK4. The same `tests/roles.out` again, through GObject rather than an Apple object system |
| | *Reading a widget back as pixels is macOS only so far; the other hosts answer no to `Capability.snapshot` rather than pretending.* |
| Windows | host not written. Everything above the host runs and is tested here |
| Android | no host yet — but `cortado.layout` builds for it and runs on an emulator, printing the same 69 goldens |

## How it is put together

```
your program
     │
cortado.bx          the .bx markup compiler — build-time only, never linked
cortado.component   components, the differ, and the applier
cortado.surface     windows, and the application that owns them
cortado.widgets     the controls
cortado.motion      the frame clock, and animation
cortado.layout      where everything goes — arithmetic, no controls
cortado.events      what the user did
cortado.platform    what this platform can and cannot do
cortado.geometry    points, sizes, rectangles
cortado.host        the flat C ABI, and the only package that names it
cortado.annotations @view · @param · @inject · @window · @command · @platform
     │
src/cortado_host.h  ── src/mac/ · src/ios/ · src/gtk4/ · src/win32/
                       (+ android)
```

**A host is a platform, not a file.** Each of the four is thirteen translation
units with the same names — `handles`, `app`, `surface`, `widget`, `view`,
`property`, `menu`, `items`, `dialog`, `system`, `introspect`, `clock`, `anim`
— so the same concern is in the same place whichever platform you are
reading. What they
share is that platform's own `internal.h`: it names AppKit or GObject or Win32
types freely, no other host includes it, and no Beans file ever sees it.

They were one file each, of 1,600 to 2,350 lines. That was readable while a
host was a handful of controls and stopped being readable well before it was
finished. `tools/check_hosts.sh` checks the union of what a platform defines,
so how a host is filed is its own business and the contract is unchanged.

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

## Components

A component is an ordinary Beans class. Its fields are its state, `render` says
what it should look like, and cortado works out the difference from the last
render and changes only that.

```beans
@view
pub class Counter extends component.Component {
    @param pub heading: string = "Order a coffee"
    @inject pub menu: Menu = new Menu()
    shots: int = 1
    price: Price = new Price()

    pub override fn render(into: component.Builder) {
        into.open("VStack")
        into.number("spacing", 14.0)
        into.number("padding", 24.0)
        into.word("align", "stretch")
            into.open("Label")
            into.text("{self.shots} shots")
            into.close()

            into.child("price", self.price)

            into.open("Button")
            into.text("Another shot")
            into.flag("enabled", self.shots < 4)
            into.on("click", fn(event: events.UiEvent) { self.add_shot() })
            into.close()
        into.close()
    }

    fn add_shot() {
        self.shots = self.shots + 1
        self.request_render()
    }
}
```

`examples/counter/` is that screen, running, with the service registered
through barista.

**Why a render does not touch the platform.** `render` produces a tree of
`Element` values. A `Differ` compares it with the last one and answers a list
of `Change`s; an `Applier` turns those into platform calls. Three things follow,
and they are the reason for the indirection:

- **Nothing is destroyed that did not change.** A native control holds focus, a
  text selection, an input-method session and a scroll position. Rebuilding one
  because its sibling changed loses all of it, visibly.
- **Renders are values, so they are testable with no platform.** `tests/diff.b`
  checks 23 reconciliation cases on every operating system with no display —
  including that reordering keyed rows emits moves and creates nothing.
- **The markup compiler has a target.** `Builder`'s methods are the ABI `.bx`
  will emit against, and they are deliberately something a person can write by
  hand, so markup is sugar over one API rather than a second one.

**Keys.** A child with a `key` keeps its control when the list around it is
reordered or filtered. Without one, children match by position — which is right
for a fixed layout and wrong for a list: remove the first of five unkeyed rows
and every row after it is told it is now the row below, so four controls are
rewritten where one should have been removed. The golden file records both
costs side by side.

**Annotations.** `@view` marks a component, `@param` a field the caller sets,
`@inject` a field the container fills. `@inject` needs a placeholder value
(`= new Menu()`) because Beans proves every field is assigned before a
constructor returns and `init` runs long before anything has a container to ask
— so prefer constructor injection for what a component cannot work without, and
`@inject` where a constructor cannot reach.

**Dependency injection** is [barista](https://github.com/beans-lang/barista),
and the whole of the dependency is one class in a *separate module*,
`cortado_app`. `cortado.component` asks for a `ServiceSource` — an interface
over `std.reflect` with two methods — so an application with its own idea of
where services come from writes twenty lines instead of adopting a container,
and cortado's own gate needs no dependency to run.

## Markup

A screen is a `.bx` file: markup on top, Beans underneath, one class.

```
<VStack spacing={14} padding={24} align="stretch">
  <Label font_size={17} text="Order a coffee" />
  <Label>$self.shots × $self.drink</Label>

  <Price drink={self.drink} />

  $if self.shots > 2 {
    <Label text="That is a lot of caffeine" />
  }

  <HStack spacing={10} justify="end">
    <Button enabled={self.shots < 4} on:click={fn(e: UiEvent) { self.add_shot() }}>
      Another shot
    </Button>
  </HStack>
</VStack>
<beans>
package site

@view
pub partial class Checkout extends component.Component {
    @inject pub menu: Menu = new Menu()
    pub drink: string = "flat white"
    pub shots: int = 1

    pub fn add_shot() {
        self.shots = self.shots + 1
        self.request_render()
    }
}
</beans>
```

```
beansc build examples/cortado_bx.b -o build/cortado-bx
build/cortado-bx build site/checkout.bx
```

**Generated code goes under `generated/`, mirroring the source tree.**
`site/checkout.bx` becomes `generated/site/checkout.b`, and the mirror hangs
off the module root — the nearest directory with a `beans.pot` — so the output
does not depend on where the compiler was run from.

```
examples/markup/
├── beans.pot
├── main.b
├── site/                  markup only; not a Beans package
│   ├── checkout.bx
│   └── price.bx
└── generated/
    └── site/              package site → markup.generated.site
        ├── checkout.b
        └── price.b
```

Mirroring rather than flattening, because **a directory is a package in Beans**
and its name is the folder's name, not what a file declares. A mirrored tree
keeps every package name it had and gains one prefix at the root, so nothing
has to be renamed as markup is added, moved or nested. It also means the two
halves of a screen are never neighbours, so nobody edits the generated one by
mistake.

**The tags are controls, not HTML.** Containers are `VStack`, `HStack`,
`VFlex`, `HFlex`, `Grid`, `Box`, `Container` and `ScrollView`; controls are
`Label`, `Button`, `TextField`, `SecureField`, `TextArea`, `CheckBox`,
`RadioButton`, `Switch`, `Slider`, `ProgressBar`, `ComboBox`, `Separator`,
`Image` and `Canvas`. A closed set, and
any other capitalised tag is a component. There is no `<div>`, no entity table,
no escaping and no `$html`: the output is a tree of native objects, and there
is nothing to inject into.

**The generated code is the code you would have written.** `.bx` is sugar over
`Builder`'s methods, not a second way of saying the same thing:

```beans
b.open("VStack")
b.number("spacing", (14) as f64)
b.word("align", "stretch")
b.open("Label")
b.text("{self.shots} × {self.drink}")
b.close()
```

**Attributes are typed, and that is where this differs most from an HTML
markup language.** latte writes every attribute as a string because HTML
attributes are strings. A control's properties are not: `spacing` is a number,
`enabled` a flag, `align` one word out of four. So the emitted call is typed
too, and `spacing={self.name}` is `expected f64, got string` at the author's
own expression rather than a string that parses to something unintended.

**The compiler is pure Beans over `std.fs`.** It links no platform host, so it
builds and runs on every operating system — including the ones whose host has
not been written.

Generated files are checked in, and `test.sh` regenerates and diffs them, so a
stale one fails the build instead of shipping. The same gate diffs
`bx/vocabulary.json`, which an editor reads, and `tools/check_vocabulary.sh`
holds the compile-time tag table against the run-time one — it caught three
container tags that markup accepted and the Builder did not, the first time it
ran.

## The controls

| tag | macOS | what it is |
|---|---|---|
| `Label` | `NSTextField` | static text |
| `Button` | `NSButton` | a command |
| `TextField` | `NSTextField` | one line of editable text |
| `SecureField` | `NSSecureTextField` | one line the platform shows as dots |
| `TextArea` | `NSScrollView` + `NSTextView` | many lines, scrolling |
| `CheckBox` | `NSButton` | on, off or mixed |
| `RadioButton` | `NSButton` | one choice of several; grouped by parent |
| `Switch` | `NSSwitch` | on or off — **not on every platform**, see below |
| `Slider` | `NSSlider` | a number in a range, optionally stepped |
| `ProgressBar` | `NSProgressIndicator` | progress, or that work is happening |
| `ComboBox` | `NSPopUpButton` | one of a list |
| `Separator` | `NSBox` | a rule between groups |
| `Image` | `NSImageView` | a picture |
| `Container` | `CortadoView` | holds children |
| `ScrollView` | `NSScrollView` | holds children, and scrolls them |

`examples/gallery` is all of them in one window, written in markup.

**Not every control is on every platform, and cortado says which.**
`WidgetKind.switch.available()` answers before anything is built, because a
toggle switch is a real control on macOS, iOS and GTK and **is not in the Win32
common controls**. Windows has toggle switches; they live in WinUI, which is a
different toolkit and not something an `HWND` can be.

The other two ways out are worse. Drawing one breaks the rule that every
control here is the platform's own — an owner-drawn imitation is wrong in ways
the user can see and the program cannot. Substituting a check box ships a
design reviewed on a Mac to Windows as something else, which is a silent no-op
one layer up. So cortado refuses, by name:

```beans
if widgets.WidgetKind.switch.available() {
    remember = widgets.Switch.of(false)?
} else {
    remember = widgets.CheckBox.of("Remember me")?
}
```

`examples/signin.b` is that, in a window you can run. A `<Switch />` in markup
refuses the same way, with `no_such_control`, because a component author never
sees a `WidgetKind` at all. `tests/controls.out` is the same bytes on a
platform that has one and a platform that has not: every line asks whether what
happened agrees with what the platform promised, so a host that quietly
substituted something would print different bytes even though it built a
control.

**A secure field is the real one.** `NSSecureTextField`, a `GtkEntry` with
visibility off, an `EDIT` with `ES_PASSWORD`. A text field with a bullet glyph
drawn into it looks the same and does none of the work: the real one keeps what
is typed out of the pasteboard, out of autocorrect's dictionary and off a
screen recording. It also answers `""` to `display_text`, so a control tree
printed to a log carries the field and not what was typed into it —
`secret.value()` is a call somebody had to write on purpose.

**A control reports the event it actually is.** A `Button` raises `activate`; a
`CheckBox`, `RadioButton`, `Switch`, `Slider` and `ComboBox` raise
`value_changed`; a
`TextField` raises `commit`. AppKit sends all of them down one selector, so the
host decides — a framework that called every action "activate" would leave each
application working the difference out again from the control's class.

**An event carries what the control said.** `event.text` is the committed text
or the chosen item, filled by the platform at the moment it raised the event,
because by the time a handler runs the control may already have moved on.

**Setting a value is silent; driving one is not.** `slider.set_value(3.0)`
changes the control and raises nothing — a program that heard about its own
writes would feed itself and never settle. `slider.set_value_as_user(0, 3.0)`
does what a person does, and the event follows. That is also how the tests
drive controls: `activate()` on a combo box would open its menu and never
return.

## Menus, dialogs and the system

**A menu command carries a role, and the platform places it.** This is the one
idea that makes a menu portable:

```beans
var edit: surface.Menu = surface.Menu.of("Edit")?
edit.add("", "", surface.CommandRole.undo, 0)?
edit.add("", "", surface.CommandRole.cut, 0)?
edit.add("", "", surface.CommandRole.select_all, 0)?
```

comes back as `Undo [mod+z]`, `Cut [mod+x]`, `Select All [mod+a]` — the
platform's own words and keys, not the ones you typed. Ask for
`CommandRole.preferences` and macOS gives you `Settings…` at Command-comma;
Windows would give you something else, under a different menu. A command with
no role is yours, and goes exactly where you put it with the title and key you
gave it.

Cut, Copy, Paste, Undo and Select All get **no target at all**, so AppKit's
responder chain finds the focused text field. Wiring them to a handler of your
own is how editing stops working in every system control in your window.

**Every dialog is asynchronous**, and that is what the platforms do rather than
a style cortado chose — a blocking `open_file()` would have to spin an inner
event loop and re-enter the render it was called from. So a dialog takes a
token and answers with an event carrying it. **A dialog always answers**: with
no visible surface to hang from, a message answers its default button and a
file dialog answers a cancel, immediately, because a sheet on an unshown window
runs no completion handler and the caller would wait forever.

**The system's own answers**, rather than constants somebody typed:
`platform.Appearance.current()` is light or dark, `window.scale()` is 1 or 2 to
hand to the layout solver, and `platform.SystemFont.body.family()` is San
Francisco here and Segoe UI there.

## Motion

**A frame clock is not a timer.** A surface can ask the platform to tell it
before every frame the display is about to show, and on three hosts out of four
that is the display's own link — CVDisplayLink on macOS, CADisplayLink on iOS,
the GdkFrameClock on GTK4. Windows has no such thing behind a plain window, so
it is a timer at about 60 Hz there, and the host says so rather than pretending.

```beans
var clock: motion.FrameClock = new motion.FrameClock(window.handle(), app.router)
clock.start(1, fn(frame: motion.Frame) {
    filled = filled + frame.delta / 3.0      // three seconds, on any display
    bar.set_value(filled)
})?
```

`frame.delta` is the point. Advance by the time that passed and the bar takes
three seconds on a 60 Hz screen and on a 120 Hz one; advance by a fixed step
per tick and it finishes in half the time on the faster machine. **No tick is
dropped or merged**, so the deltas always add up to `frame.elapsed` — a handler
that ran long gets its frames late and in order, and nothing that was supposed
to move ends up somewhere else.

The host counts the frames it hands over, and `clock.state()` reads that count
back. `tests/frames.b` compares it with the number Beans received: two
independent tallies of the same frames, so a delivery path that lost one is a
failing test rather than an animation that ends slightly early.

**An animation is described, not driven.** The frame clock is for something
whose next value you have to work out; an animation is for a value you already
know the end of, which is almost everything an interface does.

```beans
var fade: motion.Animation = motion.Animation.on(badge.handle(), motion.Animatable.opacity)?
fade.to(0.0)?
fade.duration(0.3)?
fade.curve(motion.Curve.ease_out)?
fade.start(7)?
```

On macOS and iOS that becomes a `CABasicAnimation` and the render server runs
it, at the display's rate, on a thread of its own — it keeps its timing while
the main thread is busy, and no Beans code runs for any frame of it. GTK4 and
Win32 have no render-server animation to hand it to, so they walk the same
curve themselves on a timer. The curve is defined once, in
`src/cortado_rules.h`, and the two Apple hosts hand its name to
`CAMediaTimingFunction` instead of computing it.

**The property reads as the destination while it moves.** `start` writes the
value to where it is going, and `badge.opacity()` answers that from then on:
the property is what is *meant*, the movement is what is *shown*. That is Core
Animation's model and presentation layers, and the hosts that have no
presentation layer keep the destination beside the animation so the four
agree. Cancelling is the exception, and the reason the distinction earns its
keep — it stops where it is, and the property keeps the value it was showing
rather than jumping to the end.

The end arrives as an ordinary event on the widget, registered like any other
handler, carrying the token `start` was given and whether it finished or was
cancelled. Starting a second animation of the same property replaces the
first, which reports itself cancelled; so does releasing the widget under it.

`Application.run_for(seconds)` is the other half. `run()` does not come back
until the program is done, which is right for a program and impossible for a
test — so there is a bounded run that waits with a deadline. It is what lets
`tests/frames.b` wait for a real display without being able to hang on a
machine that has none.

## The GPU

**Some things are not a tree of controls.** A chart with fifty thousand points,
a waveform, a map, a game — drawing one of those by making controls is how a
program ends up with fifty thousand views. `cortado.gpu` is the other door: the
machine's own graphics processor, opened directly.

```beans
if !platform.Capability.gpu.available() {
    // draw it with controls, or say there is no chart
}
var card: gpu.Device = gpu.Device.open()?
let shared: bool = card.shares_memory()?      // is an upload a copy, or nothing?
```

The shape of the ABI is WebGPU's rather than any one platform's — a device,
resources made on it, a pipeline that says how to draw, a pass that draws —
because that shape was designed to sit over Metal, D3D12 and Vulkan at once,
which is this header's problem exactly. **Metal fills it on macOS and iOS.**
GTK4 and Win32 answer `unsupported` to every call and `Capability.gpu` answers
no, so a program asks once instead of finding out one call at a time.
`src/gtk4/gpu.c` and `src/win32/gpu.c` say what a Vulkan or D3D12 backend would
have to bring.

**Shaders are the one difference cortado does not hide.** MSL, HLSL and SPIR-V
are three languages with three compilers, and the only way to paper over that
is to vendor a translator — a project larger than this one, whose output would
still not be exact. So `gpu.ShaderLanguage.msl.accepted()` says what the host
in front of you speaks, and a program that targets Metal and Direct3D ships two
shaders and picks one. That is more work than pretending, and it finishes.

Metal is linked into every cortado program on Apple platforms, and that was
measured rather than assumed: against a binary linking only AppKit and
Foundation, adding Metal changes the size not at all, adds three load commands,
and moves launch time less than the noise between two runs of the same binary.

### Drawing something

```beans
var card: gpu.Device = gpu.Device.open()?
var canvas: gpu.Target = card.target(640, 480)?          // pixels, not points
var shader: gpu.Shader = card.shader(gpu.ShaderLanguage.msl, source)?

var line: gpu.Pipeline = shader.pipeline("v_main", "f_main")?
line.attr(0, 2, 0)?        // attribute 0: two numbers, starting at number 0
line.attr(1, 4, 2)?        // attribute 1: four numbers, starting at number 2
line.stride(6)?            // so a vertex is six numbers
line.blend(gpu.Blend.alpha)?
line.build()?

var draw: gpu.Pass = canvas.begin(0.0, 0.0, 0.0, 1.0)?   // clears as it starts
draw.pipeline(line)?
draw.vertices(card.buffer(vertices)?)?
draw.uniform([1.0])?
draw.draw(gpu.Shape.triangles, 0, 6)?
draw.finish()?                                           // runs it, and waits

let picture: widgets.Snapshot = canvas.read()?           // top row first
```

`examples/shader.b` is this program with a Mandelbrot set in the fragment
shader: `beansc build examples/shader.b -o build/shader && ./build/shader`
writes a bitmap you can open.

**Numbers, and only numbers.** A buffer holds floats; an attribute's offset and
a layout's stride are counted in floats too. That is narrower than any of the
three backends and it is narrow on purpose — the alternative is an API where
you compute byte offsets for data you wrote as numbers and get one of them
wrong. Packed colours and 16-bit indices are the reason this will grow, and
they will arrive as their own call rather than by changing what these arguments
mean.

**A pass is synchronous.** When `finish` returns the pixels are there to read.
That is the right trade for an image a program computes and reads back. It is
the wrong one for a surface being presented sixty times a second, which is a
different call with a different contract rather than a flag on this one.

**Three blend modes, not eight blend factors.** `replace`, `alpha` and `add`:
every backend has these three and means the same by them, and a factor pair is
eight enums to combine correctly, unchecked, to arrive at one of these three
anyway.

### A canvas on screen

A GPU target is an off-screen image. To put one in a window there is a widget:

```beans
var plot: widgets.Canvas = new widgets.Canvas()
var paint: gpu.Canvas = gpu.Canvas.on(plot.handle(), card)?

clock.start(1, fn(frame: motion.Frame) {
    match paint.next() {                       // the frame it is about to show
        ok(surface) => {
            var draw: gpu.Pass = surface.begin(0.0, 0.0, 0.0, 1.0)?
            draw.pipeline(line)?               // built for Pixels.screen
            draw.vertices(quad)?
            draw.uniform([frame.elapsed])?
            draw.draw(gpu.Shape.triangles, 0, 6)?
            draw.present()?                    // hands it over, does not wait
        }
        err(problem) => {}                     // no drawable free this instant
    }
})?
```

`examples/canvas.b` is this, with a plasma shader in it and a Quit button.

**`Canvas` is an ordinary control.** The solver lays it out, it sits in the
tree, it has an accessibility role, and it is a row in `tests/roles.out` on all
four hosts. On a host with no GPU it is an empty area rather than a missing
one, which is the honest shape for a control whose contents were never the
platform's to draw. Attaching a GPU to something that is *not* a canvas is
`wrong_widget` on every host, checked before the host considers whether it has
a GPU at all — "this is not a canvas" is your bug and "this platform has no
GPU" is not.

**Three calls a frame, driven by the frame clock.** A canvas is shown when the
display shows it; drawing outside a frame is drawing the platform will not put
up. `present` hands the work to the compositor and returns — where `finish`
would wait, which is right before a readback and wrong sixty times a second.

**A canvas frame is a `Target` like any other**, so `read()` works on it. That
is deliberate: it is the one control whose contents no other call can see, and
a canvas you cannot read is a canvas whose test is somebody looking at it. It
costs a little — the drawable gives up lossless compression to be readable —
and if that ever shows, the way out is a flag on attach, not a silently
unreadable canvas.

### A shader in markup, with no shader in it

Everything above is the machinery. Most of the time what you want is *a
rectangle with an effect in it*, and that is one tag with no shader code at
all:

```xml
<VStack spacing={12} padding={20} align="stretch">
  <Label>Every pixel below is a fragment shader</Label>
  <ShaderCanvas height={120} effect="ripple" color="#4088bf" detail={26} />
</VStack>
```

```beans
import {ShaderCanvas} from cortado.gpu
```

Six effects, each taking the same attributes and ignoring the ones it has no
use for — so changing `effect="ripple"` to `effect="noise"` means renaming
nothing around it:

| effect | what it draws |
|---|---|
| `solid` | one colour; the only way cortado has to fill a rectangle with a colour at all |
| `gradient` | `color` to `color_to` in a straight line, along `angle` |
| `radial` | `color` at the middle to `color_to` at the corners |
| `ripple` | rings running outward, `detail` of them, at `speed` |
| `noise` | animated value noise between the two colours, at scale `detail` |
| `checker` | `detail` squares across; `speed` scrolls it |

Colours are written the way every stylesheet writes them — `#rgb`, `#rrggbb`
or `#rrggbbaa` — and a typo is refused rather than quietly becoming black.

**Where this stops, said plainly.** There is no honest way to express an
*arbitrary* shader in markup: a shading language spelled in angle brackets
would be harder to write than the shading language, and harder to read. So
cortado names the effects worth naming and keeps one escape hatch, which is a
fragment body:

```xml
<ShaderCanvas height={120} shader={self.plasma} />
```

```beans
pub plasma: string = r"
    float rings = sin(length(uv - 0.5) * 26.0 - seconds * 3.0);
    return float4(0.25, 0.55, 0.75, 1.0) * (0.5 + 0.5 * rings);
"
```

The body gets three things — `uv` (0 to 1 across the canvas, 0,0 at the top
left), `seconds`, and `size` in pixels — and returns a `float4`. Naming an
effect *and* writing a shader is refused: a canvas that ignored half of what it
was told is something people debug for an afternoon before reading the source.

`ShaderCanvas.wrap` and `quad_corners` are public, so a program that has
outgrown `effect=` can print what cortado was generating, paste it, and start
from the shader it was already running rather than from a blank file.

That is the whole program. `gpu.ShaderCanvas` opens the device, supplies the
vertex shader and a quad covering the area, builds the pipeline, starts a frame
clock on the surface the canvas turned out to be in, draws every frame, and
takes it all down when the component goes away. `examples/gallery/site/shelf.bx`
has one running between a progress bar and a text area.

**The shader is a function body, not a Metal program.** It gets three things —
`uv` (0 to 1 across the canvas, 0,0 at the top left), `seconds`, and `size` in
pixels — and returns a `float4`. A program that needs more than that has
outgrown this class, and the rest of this package is what it grows into.

**Markup needed no new machinery for this.** `<ShaderCanvas>` is an ordinary
component tag, the same shape as any component a project writes itself; the
only line that makes it work is the import. What did have to be added is
`Stage`: `on_mount(stage)` hands a component the controls it rendered, by the
`key` it gave them. `render` describes controls and does not have any, so
before this there was no way for a component to reach one — which is why
`on_mount`'s own documentation promised something the API could not do.

**Where there is no GPU it renders the canvas anyway** — an empty area of the
right size, in the right place — and `problem()` says why nothing is in it. A
markup screen does not fall apart on a platform cortado cannot draw on.

**A canvas with no width says so.** It is the first thing everybody gets wrong:
a column whose cross alignment is not `stretch` gives each child the size it
measured, and a control that paints nothing of its own measures nothing. That
used to be a silent black rectangle. Now it is
`this canvas is 0 by 32, so there is nothing to draw into — give it a size, or
put it in a run that stretches its children`.

### What the tests can say

`tests/gpu.out` is the same bytes through all four hosts, and the two sides run
entirely different code to produce it: every line asks whether what happened
agrees with what the capability promised. A host that could not draw but said
it could — or one that quietly did nothing — fails it.

`tests/triangle.out` is the opposite kind of test. `tests/pixels.b` reads a
control back and can only assert *shape*, because its numbers come out of a
font rasterizer that changes with every OS release. A GPU target has no such
excuse: every quad in `triangle.b` lands on a pixel boundary, so coverage is
arithmetic, and the colours are asserted exactly — 64 green pixels of 64, 32 of
64 for the top half, 16 for a quad the shader halved. It is the same bytes on
this Mac's GPU and on the iOS Simulator's, which are different hardware.

## Shipping

```
tools/bundle.sh build/gallery Gallery com.example.gallery
open build/Gallery.app
```

A bare binary runs and shows a window — that is why the examples work without
this. What it does not get is a name in the Dock and the menu bar, a place in
Launch Services, an icon, or a signature. The gate builds a bundle, lints its
plist, verifies its signature and then launches it and checks the **running
process is named after the bundle**, which only holds if Launch Services really
read the plist.

Signing is ad-hoc (`-s -`) by default: enough to run locally on Apple silicon,
not enough to distribute. That needs a Developer ID and notarisation, which
need an account — so the script does the part that can be automated and says
which part it did not.

## Porting to a second platform

A port is one directory: `src/<platform>/`, implementing every entry point
in `src/cortado_host.h`. Nothing above it changes — the Beans half already
type-checks for Windows and Android on every run, and `cortado.layout`,
`cortado.component` and `cortado.bx` have no foreign call in them at all.

**`tests/roles.out` is the definition of done.** It holds cortado's own
vocabulary — kind, accessibility role, text, enabled, hidden, child order, and
frames from a layout where every size is a constant — and nothing a platform
names. A second host prints those same bytes, and the diff is the port. The
gate refuses the file if a platform's class name ever appears in it.

`tests/shelf.out` is the per-platform companion: it holds `NSButton`,
`NSSlider`, `NSPopUpButton`. That one *cannot* be shared, and should not be —
it is the answer that proves a real native control was built rather than
something drawn, and every platform has a different one.

`tools/check_hosts.sh` holds every host in `src/` to the header. The C linker
is the real enforcement — add an entry point, forget a host, and that
platform's build fails — but a link only happens where a toolchain does, so
this does the same check on text and runs anywhere.

**There are three hosts, and the second and third are the proof.**
`src/ios/` is UIKit — a different host, a different framework, the
same header — and `./test.sh --native` builds `tests/roles.b` for
`arm64-apple-ios-sim`, runs it in a booted simulator and diffs its output
against the macOS run. Identical. Nothing above the host changed to make that
true.

The port earned its keep immediately by contradicting the design twice:

- **A platform control may refuse the frame it is given.** A `UISwitch` is 51
  by 31 and nothing else; a `UIProgressView` is 4 points tall whatever you ask.
  `roles.out` used to carry frames, on the theory that a layout with no
  measurement in it must be identical everywhere. It is — and the controls
  clamped anyway. Frames are not a portable fact, so they left the portable
  golden; `tests/layout.out` checks the solver's arithmetic on every runner and
  `tests/shelf.out` records what each platform did with it.
- **A `UISwitch` has no title.** On iOS the label beside a switch is a separate
  view, so a check box's text has nowhere to go — except the accessibility
  label, which is exactly where that string belongs on that platform and is
  what VoiceOver reads.

**`examples/gallery` runs on a phone.** The same `.bx` markup, the same
component tree, the same layout solver, twelve real UIKit controls — built with
`tools/bundle_ios.sh` and installed with `xcrun simctl install`.

The one structural thing this host does that the macOS one does not is worth
knowing, because it cost the longest to find. **A `UIWindow` belongs to a
`UIWindowScene`, and one built before the application launched belongs to
none.** Such a window can be key, visible, unhidden, correctly sized and fully
populated — every property reads right — and it renders *nothing*, not even its
own background colour. Assigning `windowScene` afterwards does not fix it. So
`ctd_attach_scene` builds a real scene window when a scene connects and moves
the view controller, with cortado's whole tree under it, across.

cortado builds its window before starting the loop because that is the order
every other platform uses and the order an application's own code reads in. A
phone is the one platform where the application does not own its startup, which
is why `ctd_app_run` was allowed not to return from the first commit.

### The GTK4 host

`src/gtk4/` is the third implementation, and the first that is not an
Apple object system: GObject instead of Objective-C, signals instead of
target/action, floating references instead of retain/release. `tests/roles.out`
is the same bytes through it.

GTK4 ships a macOS backend, which is the only reason a Linux host could be
checked here at all — `tools/gtk4.sh` builds it and runs a case, and `test.sh`
makes that a leg. It proves the file implements the contract. It proves nothing
about X11 or Wayland, which are not on this machine, and the leg says so.

Three things GTK4 does differently, each of which would be a wrong answer if
copied from the AppKit host:

- **A new widget is floating.** `gtk_button_new()` hands back a reference
  nobody owns yet, and a container takes it over when the widget is added.
  cortado's handle table owns widgets before they are parented, so the host
  calls `g_object_ref_sink` on every widget it creates — without it, the first
  `gtk_fixed_put` would silently claim the table's reference.
- **A check box has a real third state.** `GtkCheckButton` carries
  `inconsistent` as a property of its own rather than as a drawing mode, so
  `P_INDETERMINATE` maps straight onto it. AppKit gets there through
  `allowsMixedState`, which also changes what clicking cycles through.
- **Per-widget style providers are gone in GTK4.** Font size is set by adding
  a CSS class and installing one provider on the display, not by attaching a
  provider to the widget — `gtk_style_context_add_provider` is deprecated and
  compiles to a warning that `-Wall -Wextra` turns into noise the build cannot
  ignore.

The Linux build needs GTK4's include paths, and there are twenty of them that
differ on every machine. They are not written into `beans.pot` by hand — a
manifest that listed them would name one computer. `beansc pot update --system
gtk4 linux` generates the `cflags linux` and `link linux` rows from
`pkg-config` between markers, and re-running it updates them in place.

**No Windows host exists yet**, and none is claimed.

## Building

```
./test.sh              # the interpreter leg, the gates, cross-target checks
./test.sh --native     # also build and run every case as a real binary
./test.sh --sanitize   # also every headless case under ASan and UBSan
```

**The gate runs on three platforms.** A booted iOS simulator adds a leg that
builds `tests/roles.b` for `arm64-apple-ios-sim`, runs it there and diffs it
against the macOS run. An attached Android device or emulator, with
`ANDROID_NDK_HOME` set, adds one that builds `tests/layout.b` for
`aarch64-linux-android` and diffs its 69 goldens the same way. Both skip with a
stated reason when their platform is not available, and an undeclared skip
fails the run.

The Android leg is the layout engine and not the component layer, and that is
the honest shape of things: `cortado.layout` has no foreign call in it at all,
so it builds and runs on a phone with **no host whatsoever**. The component
layer reaches `cortado.host`, and there is no Android host — that is JNI work,
and it is not done.

The sanitizer leg is not about the Beans half — the compiler's own gate covers
that. It is about the host: fifteen hundred lines of Objective-C with manual
retain and release, a handle table indexed by arithmetic, and a string boundary
that copies bytes both ways. `csrc` does not pass sanitizer flags to a
manifest's C sources, so `tools/sanitize.sh` compiles the host itself with them
and links by hand. It was checked by putting a one-past-the-end read into the
handle table and watching UBSan name the line.

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

**The reconciler is checked against a second implementation of itself.**
`tests/diff.b` holds hand-written cases and says what the differ emits for
each; that is the readable half and it is not the whole job, because
hand-written cases cover the shapes somebody thought of. `tests/sweep.b` is the
other half: four hundred generated tree pairs, diffed, and then re-applied by a
reference applier written inside the test that shares no line of code with
`component.Applier` and knows nothing about how the differ works. The contract
is one sentence — *applying a diff to the old tree must produce the new tree* —
and everything a reconciler can get wrong breaks it. Its golden carries the
tally of edits the sweep produced, so a sweep that stopped generating moves is
visible rather than quietly green. Deleting the differ's rule that a dropped
property goes back to its default produces 38 faults; breaking the keyed move
produces 63.

`tests/applied.b` points the same idea at the applier that really exists. The
sweep's reference applier proves the *edit list* is right and says nothing
about the applier that ships, so this one drives `component.Applier` — the one
that makes and moves real AppKit controls — down two roads to the same place:
build `before` and apply the diff, or build `after` directly in a second
container. Then it reads both live widget trees back off the platform and
requires them to be identical. Nothing in the file says what the answer should
look like; the assertion is that the cheap path and the obvious path agree.
Making `move` a no-op in the applier produces 12 faults, and dropping property
writes produces 32.

**`tests/leaks.b` is the gate for the one hazard the design flagged and could
not design away.** A stored callback is invisible to the cycle collector, so a
per-widget closure capturing its own widget would keep that widget, its
component and everything behind it alive forever with nothing on screen to show
for it. cortado's answer is that handlers are not stored per widget at all —
one platform callback for the process, handlers in a table keyed by handle —
and this is what that claim is worth: a thousand handler-bearing controls, torn
down ten times, asserting that the router empties, that every control is dead
at the platform, that a reference the *application* still holds is dead too,
and that the component's own destructor ran.

Ten thousand is not arbitrary. The handle table is 8192 slots, so a run that
size only finishes if released slots are reused — which is the second thing
this file found.

Writing it turned up two real defects, and `tests/mount.b` had been checking
the same teardown with about five controls and passing:

- **`Mount.close` released nothing.** It emptied the container and the router
  table, but the layout sheet keeps a `Widget` per node and `close` never
  cleared it — so every native control a screen ever built stayed alive until
  the whole `Mount` was dropped. A screen closed and reopened held that many
  screens' worth of AppKit objects.
- **The handle table never reused a slot.** `ctd_track` only ever handed out
  the next one, so a program that made and destroyed widgets — which is any
  program with a list in it — died after 8192 of them however few were alive
  at once. The generation in every handle exists precisely to make reuse safe;
  it just was not being used.

**Text is tested at the edges, not in the middle.** `tests/text.b` sends an
astral emoji, a combining mark beside its precomposed twin, and right-to-left
and CJK text through four kinds of control and reads each back. The combining
pair has to stay *different* — a host that normalised would hand back a string
that is equal on screen and different in bytes, and a program comparing what it
wrote with what it read would disagree with itself. Writing this found that a
string with an embedded NUL went out whole and came back truncated on every
host, which is fixed and which the file now pins down.

**`tests/pixels.b` asks the one question cortado does not already know the
answer to.** Every other check reads back a property the program itself set, so
a host that stored each value in a dictionary and never spoke to the platform
would pass all of them. This one reads the control back as pixels. It is
deliberately not a golden of an image — goldening pixels means goldening a font
rasterizer, which changes on an OS point release and teaches a team to
re-record the file. What it asserts is what holds across releases and themes:
an image is the size asked for and four bytes a pixel, an empty box is one
colour all over, a box with a real control in it is not, and hiding that
control puts the image back exactly. The last is the negative control — a
snapshot that always answered the same blank bitmap would satisfy the first
three.

## License

MIT.
