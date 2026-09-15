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

## Installing

cortado is compiled by `beansc`, so install [the Beans
compiler](https://github.com/beans-lang/beans) first.

```
git clone https://github.com/beans-lang/cortado
git clone https://github.com/beans-lang/barista
cd cortado && ./tools/install.sh
```

That builds `cortado` and puts it beside `beansc` in `$BEANS_HOME/bin`, or
`~/.beans/bin` when that is unset. Pass a directory to choose your own:
`./tools/install.sh /usr/local/bin`. It finds the compiler the way everything
else here does — `$BEANSC`, then `$BEANS_ROOT/build/beansc`, then
`../../beans/build/beansc`, then `PATH` — and says so rather than guessing if
there is none.

**barista is cloned beside it, not inside it.** cortado's dependency injection
is barista, and a scaffolded project names it as the sibling of the cortado
checkout — so the two directories have to sit next to each other.

**There is no download.** cortado has no published release yet, so the binary
comes from the checkout. That is also the arrangement that keeps it honest
while it moves: the generator and the `cortado` package a project depends on
come out of one tree, and a generated file written by one version against a
library from another is exactly the silent staleness `cortado check --drift`
exists to catch.

`cortado-bx` is installed alongside. It is the same program under its older
name, kept because the editors' vocabulary and a good deal of writing still
name it.

**An application does not need cortado to build.** A project's `generated/` is
checked in, so a clone compiles with plain `beansc` and no cortado binary
present at all — which is how `./test.sh --native` builds every example here.
`cortado` is what you need to *write* a project: to scaffold one, and to
regenerate the markup as part of every build.

## Building an application

```
cortado init myapp --cortado ../cortado && cd myapp
cortado run
```

`--cortado` is the checkout you cloned, and it is asked for rather than guessed:
a project's `beans.pot` names cortado and barista with `require path` rows, and
a row pointing at a directory that is not there fails later with a message about
a missing package rather than about the row. Leave the flag off when you are
making a project inside this workspace — then the checkout is found by walking
up, and `init` says so instead of writing a manifest it cannot stand behind.

`init` writes a project that builds and renders on the first run: a screen, a
component the screen reuses, an injected service, the two manifests, and the
generated half of the markup.

```
myapp/
├── beans.pot        the module, and what it depends on
├── cortado.pot      the application: name, bundle identity, profiles
├── main.b           four lines of code
├── screens/         one .bx per screen
├── components/      .bx parts a screen reuses
├── services/        plain .b — injected, no UI, testable with no window
├── models/          plain data
└── generated/       the .b half of every .bx, mirroring its folder
```

**There is no ViewModel folder, and that is a decision.** A `.bx` file is
already both halves: markup on top, a `partial class` holding the state and the
commands underneath, in one file the compiler keeps in step. A separate view
model could not be bound to — cortado has no binding engine, so it would
forward every property by hand and call `request_render()` itself. What a view
model is *for*, logic you can exercise without a screen, is what `services/`
is, and a service needs no window at all.

**Every build regenerates the markup first.** Markup and the code built from it
are two files, and any process where a person can compile one without the other
eventually ships the pair out of step — a generated file that still compiles,
still renders last week's screen, and says nothing. `cortado build` cannot
produce one. `cortado check --drift` is the gate form, for the ways a file can
go stale that a build never sees: a merge, or somebody running `beansc`
directly.

**Two configurations, the way `dotnet` has two.**

| | `beansc` | where it lands |
|---|---|---|
| `cortado build` | `--debug` — `-O0`, frame pointers, DWARF line tables | `build/debug/` |
| `cortado build -c Release` | `--release` — `-O3`, `NDEBUG` | `build/release/` |

Every cortado build documented before this passed *neither* flag, which is a
third mode that is unoptimised **and** has nothing for a debugger to attach to.
The two profiles write to different directories so switching never silently
overwrites the other one's binary, and `beansc`'s object cache keys on both
flags, so switching back is not a rebuild.

```
cortado build [-c Release]   regenerate, then compile
cortado run                  build, then launch it; after -- goes to the program
cortado watch                build, run, and do it again on every change
cortado check [--drift]      type-check; --drift fails on a stale generated file
cortado generate             the markup only — `cortado-bx` is this, under its
                             older name, and calls the same code
cortado clean [--generated]  remove build/
cortado publish              a Release build, wrapped as a .app and signed
```

`cortado.pot` is the application's own manifest, beside `beans.pot` because the
compiler refuses a manifest row it does not know — which is the right rule, and
the reason a bundle identifier and a usage description have nowhere to live in
`beans.pot`:

```
name       Cask
identifier com.example.cask
version    0.1.0
icon       assets/cask.icns

markup     screens
markup     components

profile release
    out    build/release
    lto    true

plist NSCameraUsageDescription "to scan a receipt"
```

**A `.bx` outside every `markup` folder is an error**, not a file quietly left
alone — a screen nothing regenerates is the same silent staleness by another
road. The refusal names the folder to add.

The window's size and title come from `@window` on the root component, so they
live beside the screen they describe and a tool can read them without running
the program. `cortado_app.run_main` is the nine steps between `main` and a
screen on the display — the container, the application, the window, the mount,
the render loop, and taking all of it back down in the right order:

```beans
fn main() {
    var options: cortado_app.AppOptions = new cortado_app.AppOptions()
    cortado_app.run_main<Home>(options)
}
```

It also gives every application `--dump`: the screen mounted headless, the
widget tree printed, exit. That is what makes a project's own gate possible
from its first commit, on a machine with no display.

Two hooks are on `AppOptions`, for the two things an application owns and
cortado does not. `on_ready` runs once the screen is mounted and its controls
exist — which some things genuinely need: a split view refuses a divider wider
than itself, so a divider written inside `on_mount`, where the control exists
with no frame at all, is refused by every host and is fine one pass later.
`on_closing` runs after the loop, for a database to close or a file to flush.
`examples/cask` is both of them, and its `main.b` is now the database and
nothing else.

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

var page: layout.LayoutNode = sheet.group("page", container, body)?
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

Four algorithms, each its own class: `StackLayout` (a row or a column that
gives every child the size it measures), `FlexLayout` (the same, with children
sharing out the space that is left over, and `set_wrap` to break the run into
lines when they do not fit), `GridLayout` (tracks that are fixed, automatic or
a fraction of what remains), and `AbsoluteLayout` (layers in one box, each
placed by its insets). Every one takes padding, spacing, main-axis
justification and cross-axis alignment, and every child may carry a margin,
size bounds, a grow and shrink weight, and an alignment of its own. In markup
every stack is a `FlexLayout`; `StackLayout` is for a tree built by hand.
Padding and margin are both `geometry.EdgeInsets` — `all(8.0)`,
`symmetric(16.0, 8.0)` or `of(top, right, bottom, left)` — so a lopsided box
is one call, not four. A child may also ask for a share of its room
(`width_percent`, `height_percent`) and a shape (`aspect_ratio`); the markup
section below says how each resolves.

Three decisions are worth knowing about, because each is a class of bug the
engine does not have:

**The engine never touches a platform.** It asks an integer key how big it
wants to be, through one injected interface with one method
(`layout.Measure`). `TableMeasure` answers from a table, so all 69 layout
goldens run with no display, no window server and no foreign call — on Linux,
on Windows, under the tree interpreter and as a native binary. A frame that
comes out wrong is a solver bug and can be nothing else. `WidgetLayout` is the
other implementation: it asks the real control.

**A scroll view is the one node bigger than its frame.** Everything else fills
the box it is given; a `<ScrollView>` measures its child with the scroll axis
unbounded and places it at *that* height, then tells the platform how big the
thing behind the viewport is (`ctd_view_set_content_size`). That number is
cortado's, worked out once in `layout.ScrollLayout` — Win32 used to infer it
from the children's frames inside `set_frame`, one host answering a question
the other three did not.

Two things about it are refused rather than guessed. It holds **one** child,
because every toolkit here scrolls a single content view and the extras would
land on top of it. And it must be told a height — `height={...}`, or
`flex={1}` inside a `<VStack>` — because a scroll view in a run that hands out
no height takes its content's height and scrolls nothing, silently. Its
content is never shorter than the viewport, so a `flex={1}` child inside it
has room to grow when the content is short and scrolls when it is tall.

```
<VStack padding={16}>
  <ScrollView flex={1}>
    <VStack spacing={10}> ... </VStack>
  </ScrollView>
</VStack>
```

**A run that spills says so.** A child that will not shrink, a grid of fixed
columns wider than its box, a layer placed past an edge: the layout dump
prints `overflows by N` on the run, and `Mount.overflows()` counts them, so a
screen's own dump can assert zero at every size. It is a number and not a
refusal, because overflow is often right — a `min_width` keeping a control
usable, a scroll view's content — and a refusal would fail a solve on every
frame of a window dragged small.

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

**Reading the window.** `self.viewport()` is the content size the mount lays
the component out in, as of its last render — so a render can decide by it.
Most screens never need to: what fits is the layout's to decide, and a child
that should go when its box is narrow says so with `hide_below` and no code
at all. `viewport()` is for the render that needs the number itself:

```
<Sidebar hide_below={600} />
$if self.viewport().width < 600 { <Label text="a phone-sized window" /> }
```

**Reading it is what declares it.** A render that calls `viewport()` is
rendered again after every resize — once, on the next refresh, however many
resize events a drag produced. One that never calls it is laid out again and
not rendered, which is why this is tracked rather than defaulted on: most
screens never read their size, and a resize that re-rendered every one of them
would pay for that on every frame of the drag. `follows_viewport()` is still
there to override when a screen wants a different answer, but nothing has to
keep two places in step any more — and a screen that read the room and forgot
to say so used to go stale for ever.

**A size that is a share of the room.** A control property is not a layout
number: `font_size`, `padding` and `corner_radius` leave a render as plain
points and reach the platform before the solver runs, so there is no
`font_size_percent` and there could not be one. What there is instead is the
share, worked out where the room is already known:

```
<Label font_size={self.vw(10, 28, 64)} text="Petrichor" />
```

A tenth of the window's width, never below 28 points and never above 64 —
the web's `clamp(28px, 10vw, 64px)`, in the one call that needs no second
method on the class. `vh` is the same on the other axis. Bounds the wrong way
round take CSS's answer and the low one wins.

**And a share of a component's own box.** `viewport()` is the *window*, and the
box a component is laid out in is usually much smaller: in
`examples/gradients` the title's column is 620 points inside a 900-point
window, because there is padding and a shelf of colour chips beside it. `cw`
and `ch` are shares of that box, and `box()` is the box itself:

```
<Label font_size={self.cw(10, 28, 64)} text="Petrichor" />
```

Three things follow from it, and they are the whole contract.

*It is the box from the last pass*, the way `viewport()` is the room from the
last render — this is `onLayout` in React Native, not a measurement taken
during the render. The mount lays out, hands every component its box, and
renders again the ones that read it.

*It belongs to a component*, because a component is the smallest thing with a
box of its own. To size a sub-part by its own box, make it a component — which
is what you do in React Native too.

*A box that decides itself is refused.* A component whose own content settles
its box cannot also be sized from that box: the layout would never converge.
The mount lays out and renders up to four times for a screen whose boxes are
still moving — a chain of components each sized by its parent settles one link
a pass — and then refuses, naming what would not settle, rather than laying out
for ever. `override fn on_layout(frame: geometry.Rect)` is the hook for
anything else that has to happen when the box moves.

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

  <Tile title="Your order" rush={self.rush}>
    $slot:cap as t: string { <Label font_size={13} text={t} /> }
    <Label>$self.shots × $self.drink</Label>
    <Price drink={self.drink} />
  </Tile>

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
cortado generate                    # every markup folder cortado.pot names
cortado generate screens/home.bx    # one file
cortado generate screens            # every .bx under it, however deep
```

`cortado build` and `cortado run` do this first, every time, so a hand-run
generate is for the times you want only the generated code. `cortado-bx` is the
same work under its older name — `build/cortado-bx build screens` — and calls
the same code rather than carrying a second copy of the walk.

**Hand it the folder.** A shell glob is not recursive — `site/*.bx` silently
misses `site/parts/` — and what that produces is the worst kind of failure
this library has: a *stale* generated file that still compiles, still renders
last week's screen, and says nothing. A directory input means cortado-bx
decides what is in the folder, and the answer cannot come up one short. A
directory with no markup in it is an error rather than no work.

**Generated code goes under `generated/`, mirroring the source tree.**
`site/checkout.bx` becomes `generated/site/checkout.b`, and the mirror hangs
off the module root — the nearest directory with a `beans.pot` — so the output
does not depend on where the compiler was run from. The header naming the
source is written relative to that same root, so the *bytes* do not either:
`cortado generate screens` and `cortado generate ./screens` from one directory
up produce the same file, and a drift gate does not call one of them stale.

```
examples/markup/
├── beans.pot
├── main.b
├── site/                  markup only; not a Beans package
│   ├── checkout.bx
│   ├── price.bx
│   ├── tile.bx
│   └── parts/
│       └── badge.bx
└── generated/
    └── site/              package site → markup.generated.site
        ├── checkout.b
        ├── price.b
        ├── tile.b
        └── parts/         package parts → markup.generated.site.parts
            └── badge.b
```

**A component in a nested folder needs one import line and nothing else.**
`parts/badge.bx` generates into `generated/site/parts/`, which is the package
`parts`, so `tile.bx` — the file whose markup names the tag — writes

```beans
import {Badge} from markup.generated.site.parts
```

in its own `<beans>` block — cortado-bx copies that through byte for byte. The
tag is spelled `<Badge rush={self.rush} />` either way; nesting costs the
import and buys the folders. `examples/markup` is that, and
`tests/markup.out` follows one parameter across the package boundary and
watches the label change.

Mirroring rather than flattening, because **a directory is a package in Beans**
and its name is the folder's name, not what a file declares. A mirrored tree
keeps every package name it had and gains one prefix at the root, so nothing
has to be renamed as markup is added, moved or nested. It also means the two
halves of a screen are never neighbours, so nobody edits the generated one by
mistake.

**The tags are controls, not HTML.** Containers are `VStack`, `HStack`,
`Grid`, `Box`, `Container` and `ScrollView`; controls are
`Label`, `Button`, `TextField`, `SecureField`, `TextArea`, `CheckBox`,
`RadioButton`, `Switch`, `Slider`, `Stepper`, `ProgressBar`,
`LevelIndicator`, `ComboBox`, `Table`, `SearchField`, `Spinner`, `Link`,
`Segmented`, `GroupBox`, `Separator`, `Image` and `Canvas`. A closed set, and
any other capitalised tag is a component. There is no `<div>`, no entity table,
no escaping and no `$html`: the output is a tree of native objects, and there
is nothing to inject into.

**You extend a control by wrapping it, not by subclassing it.** A
`widgets.Button` owns one native object and is not a `Component`, so a subclass
of it is not a tag — `Mount.obtain` refuses it by name. A component that
*renders* a `<Button>` is a tag, with no registration anywhere, and that is the
supported shape: `examples/gallery/site/FancyButton.bx` is a coloured button in
eight lines of markup, used as `<FancyButton title="Clear" tint={self.accent}
on_press={...} />`. Its attributes are its own fields, so it names them itself.

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

**A component can take a template, and `$slot` is where it puts it.** A `<Tile>`
decides *where* its content goes; the screen around it decides *what* the
content is. The children of a component tag are its default template, and a
named one is written with a body:

```
<Tile title="Your order" rush={self.rush}>
  $slot:cap as t: string { <Label font_size={13} text={t} /> }
  <Label>$self.shots × $self.drink</Label>
  <Price drink={self.drink} />
</Tile>
```

The component declares each template as an ordinary field and places it:

```
<VStack spacing={6}>
  $slot:cap as self.title
  <Badge rush={self.rush} />
  $slot
</VStack>
<beans>
@view
pub partial class Tile extends component.Component {
    @param pub title: string = ""
    @param pub rush: bool = false

    pub body: fn(Builder) = fn(_b: Builder) {}
    pub cap: fn(Builder, string) = fn(_b: Builder, _t: string) {}

    pub fn init() { super.init() }
}
</beans>
```

A default that draws nothing is the author's own field initializer, so a tile
nobody gave a template to is empty rather than broken and cortado needs no
concept for "no template". Six forms: four place a template —

```
$slot                       the tag's children, as `self.body`
$slot(<expr>)               any fn(Builder) expression
$slot:<name>                the field of that name
$slot:<name> as <expr>      that field, handed a value
```

and two define one, which only reads that way inside a component tag:

```
$slot:<name> { ... }              a template taking nothing
$slot:<name> as <p>: <Type> { }   one taking a parameter
```

**A template is written in one component's file and run in another's**, and
that is the part worth knowing about. The body above is *written* in
`checkout.bx`, so `self` inside it is the screen and it reads the screen's
fields; it is *run* against the tile's builder, so its controls land where the
tile put the `$slot`. That makes the placement site part of a child's identity:
`<Price>` inside the template and `<Badge>` in the tile's own markup would
otherwise be one child asking for one key, and placing a template twice would
make one child rather than two. `Builder.fragment` keys everything a template
writes by the site that placed it — the `$slot`'s place in the file *and* the
row of the `$for` around it, the same two-part identity a component tag has —
and `tests/slots.b` is the case: the same template at two sites, a template
between two sibling tags, a template placed inside a template, and a template
placed once per row of a loop.

**`ref={self.tile}`** on a component tag hands back the instance the tag built,
into a field declared `Option<Tile>`, once every parameter and template on it
is set. On a *control* it is refused: a control is made and owned by the mount,
not by the render that described it, so a control is named with `key="..."` and
reached from `on_mount` through `Stage.control(key)` or `Stage.widget(key)`.

**A component tag takes what its root asks of the run around it.** `margin`
and its six edges, `grow`, `shrink`, `basis`, `width`, `height`, `x`, `y` and
`align` are *placements*: written on the tag by the parent, applied to the
child's root after it has rendered, so the parent's word is the last one. It is
checked against the container the tag sits in — `grow` inside a `<VStack>` is
refused the way it is on a control. Everything else on a component tag is a
parameter, by its Beans name, `padding` included: what a component keeps inside
itself is its own, and one that wants it set from outside declares the field
and forwards it. A component whose *public* field shares a placement's name is
refused by name, because one spelling would otherwise mean two things.

```
<VStack spacing={12} align="stretch">
  <Tile flex={1} margin_x={8} title="Today" />
  <Price height={44} align="end" drink={self.drink} />
</VStack>
```

By hand it is the value `child` and `show` answer:
`into.child<Price>("price", fn(c: Price) { c.drink = self.drink }).number("height", 44.0)`.

**What cortado's markup refuses, it refuses by name.** `<!DOCTYPE>`, `$html`,
`attrs={...}` and `preserve` are all real in the HTML-shaped markup language
this one grew out of, and none of them has anything here to act on — there is
no document to declare, nothing to inject into, no bag of pass-through
attributes, and nothing outside cortado that writes into a control tree. Each
is answered with a sentence about the program rather than left to fall through
to "no such attribute" or, worse, emitted as a `Builder` call that does not
exist. `tests/markup_refusals.b` asserts the *message*, not the refusal,
because most of these were refused either way and the whole value is which
sentence the author reads.

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
| `SearchField` | `NSSearchField` | a field that says what it is for |
| `SecureField` | `NSSecureTextField` | one line the platform shows as dots |
| `TextArea` | `NSScrollView` + `NSTextView` | many lines, scrolling |
| `CheckBox` | `NSButton` | on, off or mixed |
| `RadioButton` | `NSButton` | one choice of several; grouped by parent |
| `Switch` | `NSSwitch` | on or off — **not on every platform**, see below |
| `Slider` | `NSSlider` | a number in a range, optionally stepped |
| `Stepper` | `NSStepper` | two arrows that nudge a number |
| `LevelIndicator` | `NSLevelIndicator` | how full something is — **not everywhere** |
| `ProgressBar` | `NSProgressIndicator` | progress, or that work is happening |
| `ComboBox` | `NSPopUpButton` | one of a list |
| `Separator` | `NSBox` | a rule between groups |
| `Image` | `NSImageView` | a picture |
| `Table` | `NSTableView` | rows and columns, filled by asking |
| `Spinner` | `NSProgressIndicator` | work with no known end — **not everywhere** |
| `Link` | `NSTextField` + a link attribute | words that go somewhere |
| `Segmented` | `NSSegmentedControl` | a few choices, all on screen — **not everywhere** |
| `GroupBox` | `NSBox` | a titled frame around a group — **not everywhere** |
| `Container` | `CortadoView` | holds children |
| `ScrollView` | `NSScrollView` | holds children, and scrolls them |

`examples/gallery` is all of them in one window, written in markup.

**Not every control is on every platform, and cortado says which.**
`WidgetKind.switch.available()` answers before anything is built. Two controls
need the question today. A toggle switch is real on macOS, iOS and GTK and
**is not in the Win32 common controls**; a level indicator is real on macOS and
GTK and has no counterpart in UIKit or the common controls — a `UIProgressView`
is not one, because a progress bar is work with a beginning and an end and a
level is a reading that goes up and down and never finishes. Windows has toggle switches; they live in WinUI, which is a
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

**A control's other strings are keyed.** `set_text` is the text a control *is*
— a button's title, a field's value. A field also has words it shows while it
is empty, and a `Table` will have a URL when links land, so those go through
`ctd_set_string(widget, CTD_S_HINT, ...)` rather than one entry point each: a
new string costs four `switch` cases, not four implementations. Which kinds
have which key is cortado's rule, in `src/cortado_rules.h`, and
`tests/strings.out` is that rule as a golden — including that the hint and the
value are different strings, which a host that stored one where the other goes
would otherwise pass.

**Everything that holds children is one class.** `ChildHolder` owns the child
list, the ordering, the platform calls and the lifetime; `Container` is that
built as a plain box and `GroupBox` is that built as a titled frame. Two copies
of a child list would be two things to keep in step, and the reconciler
downcasts to `ChildHolder` so a new kind that holds children needs nothing from
it.

**A link opens its URL and raises nothing.** That is a decision. The four
platforms disagree about who follows a link — AppKit and GTK do it themselves,
a `SysLink` reports the click and leaves it to the program — and **none of them
lets a program intercept the click** and route it somewhere else. So cortado
does not promise an event it could only raise on some hosts. A screen that
needs to handle the click itself wants a `Button` with the words in its title,
which is a different control and says so.

Two hosts keep the target *inside* the control's own text: an attributed string
on the Mac, `<a href="...">words</a>` markup on Windows. So writing the words
must not drop the link, and reading the target back must not answer the markup
— which is what `tests/strings.out` checks, and what caught the first version
losing every URL to a message sent to a `nil` dictionary.

**Every stack in markup flexes.** `<VStack>` and `<HStack>` share out their
leftover by `grow` and take back overflow by `shrink`, `flex={1}` is the three
numbers at once, and `wrap` breaks the run into lines — there is one family of
container to choose from, as in Yoga. The old `<VFlex>`, `<HFlex>`, `<VWrap>`
and `<HWrap>` are refused by name with the tag to write instead. A hand-built
`StackLayout` keeps refusing `grow` as `grow_in_a_stack`: it gives every child
the size it measures, and the silent version of that cost three afternoons.

**A table asks for its cells; it does not hold them.** This is the one control
cortado does not build out of widgets, and the reason is the only one that
matters: a list long enough to need a table is long enough that building it
shows. Ten thousand rows of four columns is forty thousand controls, forty
thousand frames for the solver, and a reconciler pass over all of them every
time one cell changes — for a screen with thirty rows on it.

```beans
class Book implements widgets.TableRows {
    pub fn row_count() -> int { return 50000 }
    pub fn cell(row: int, column: int) -> string { ... }
}

var orders: widgets.Table = widgets.Table.of(["#", "Drink", "Shots", "Price"])?
orders.set_source(new Book())?
```

`NSTableView` calls that a data source, Win32 calls it `LVS_OWNERDATA`, GTK4 a
list model, UIKit a table view data source; cortado calls it the same thing all
four do. It is the one place the platform calls **into** Beans, and the shape
is the event sink's: one function pointer for the whole process, registered
once, routed on the table's handle. Not one per table — a stored callback per
control is a leak by construction.

The one rule `cell` has to keep is that it **returns**. It runs on the UI
thread while the platform is drawing: no waiting, no joining, no fetching. If
the data is not there yet, answer what you have and call `reload()` when it
arrives.

`tests/table.out` is where "it does not hold them" stops being a claim. The
source counts how many times it is asked, and a table of 100,000 rows asks for
no more cells than one of 1,000 — on AppKit and UIKit that number is zero until
something draws, on GTK it is one screenful. `examples/ledger.b` is fifty
thousand rows in a window.

**A slider's increment is write-only, and a stepper's is not.** AppKit has no
increment on a slider: a stepped `NSSlider` is one with tick marks it has to
land on, so what the host holds is a count of positions and not the number that
was written. Reconstructing it is exact when the step divided the span evenly
and quietly wrong otherwise — and Win32 *can* answer, which is the trap, since
one platform answering a number the other three cannot is a divergence that
reads as a feature. So `ctd_get_real(CTD_P_STEP)` is `wrong_widget` on anything
but a `Stepper`, everywhere. `tests/numbers.out` is that, per kind, on every
host.

**A secure field is the real one.** `NSSecureTextField`, a `GtkEntry` with
visibility off, an `EDIT` with `ES_PASSWORD`. A text field with a bullet glyph
drawn into it looks the same and does none of the work: the real one keeps what
is typed out of the pasteboard, out of autocorrect's dictionary and off a
screen recording. It also answers `""` to `display_text`, so a control tree
printed to a log carries the field and not what was typed into it —
`secret.value()` is a call somebody had to write on purpose.

**A control reports the event it actually is.** A `Button` raises `activate`; a
`CheckBox`, `RadioButton`, `Switch`, `Slider`, `Stepper` and `ComboBox` raise
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

Three controls make that rule hard to keep, because their platforms treat the
state as the user's: a split view is re-divided by `-setFrame:` and says a
divider moved, `-setPosition:` says it again, and a table posts a selection
change for `-selectRowIndexes:` exactly as it does for a click. All three used
to reach the program. `examples/cask` found all three on its first run — a
sidebar asked for at 210 points came up at half the window, and a navigator
that opened a tree node and selected it heard the selection as a click and
shut the node again. Each host now carries one counter, `g_writing`, and
`tests/panes.b` and `tests/table.b` fail when it is taken out.

### Which control has which property

`<Label checked />` is refused where it is written, and the refusal says where
`checked` does belong:

```
probe.bx:1:8: <Label> has no checked — checked is carried by CheckBox, RadioButton, Switch
```

**The answer lives in one place.** `ctd_kind_carries(kind, space, key)` asks
`src/cortado_rules.h`, and every host's implementation of it is the same three
lines, because a host that decided for itself is how this went wrong in the
first place. Three of these rules had four different answers before it existed,
one per platform, none of them written down anywhere:

| | macOS said | iOS said | GTK4 said |
|---|---|---|---|
| `editable` on a `Label` | yes — a label is an `NSTextField` | no | no |
| `editable` on a `TextArea` | no — it is an `NSScrollView` | yes | yes |
| `font_size` on a `Container` | no — it is not an `NSControl` | no | yes — CSS styles anything |
| `alignment` on a `Link` | yes | no | no |

Each host was asking its own object system, and the object systems disagree —
which is the same mistake `CTD_P_ENABLED` was fixed for once already.
`tests/attributes.b` is what keeps it fixed: it walks every tag against every
attribute for the two written tables, then builds a real control of every kind
the platform has, sets every property on it, and fails when what happened is
not what the rule promised.

**Three facts, three answers, and merging any two of them costs you a bug.**

- *this control has no such property* — `wrong_widget`, the same on every
  platform, and what `carries` answers
- *this platform cannot do it* — `unsupported`, and it differs; a slider
  carries a step everywhere, and iOS says so plainly because a `UISlider` is
  always continuous
- *this platform has no such control* — `WidgetKind.available()`

A caller who cannot tell the first from the second writes a program that works
on one desktop and is quietly inert on another.

Layout names are no control's to refuse. `spacing`, `padding`, `grow` and the
rest belong to the layout and never reach the control; what refuses them is the
tree — `<Label spacing={4} />` has no children to space, and the render says so.

**Padding and margin come in seven spellings each.** The bare name writes all
four edges; `padding_x` and `padding_y` write one axis; `padding_top`,
`padding_right`, `padding_bottom` and `padding_left` write one edge. `margin`
has the same six. Each writes only the edges it names, in source order, so
`padding={8} padding_x={16}` is 8 above and below and 16 at the sides — and the
reverse order is 8 all round, because `padding` wrote last. That is the rule a
CSS shorthand follows, and it is the one that lets a base value be written
once and adjusted on one side.

```
<VStack padding={8} padding_top={20} align="stretch">
  <Label margin_left={12} text="hangs in from the left" />
  <Button margin_y={4}>Order</Button>
</VStack>
```

A margin is the child's own, so every control takes one; padding is a
container's, so `padding_left` on a `<Label>` is refused the way `padding` is.

**A run that wraps.** `wrap` on a stack: children go along the main axis
until the next would not fit, then start a new line, with `spacing` between
neighbours and `line_spacing` between lines. Each line is a flexing run of its
own — `grow` fills that line's leftover, `justify` places that line, `align`
sits a child within its line — and a child wider than the room takes a line of
its own and shrinks to fit. A shelf of tags that reflows as the window narrows
is one attribute:

```
<HStack wrap spacing={8} line_spacing={8}>
  $for tag in self.tags { <Button key={tag} text={tag} /> }
</HStack>
```

**Hidden by the room, not by a line of code.** `hide_below={620}` shows a
child only while the box around it is at least 620 wide, and `hide_above` is
the other bound. The layout decides it on every pass, against the *parent's*
box rather than the window, so a legend that goes when its band is narrow is
one attribute and no render runs when a drag crosses the line — the control is
culled from the run, takes no room and no spacing, and the sheet hides it.
`hidden` does the same at every width: a hidden control leaves the layout. A
bound written on a screen's root is refused, since nothing contains it.

**A label wraps.** Offered less width than its words need, a `<Label>` answers
the height it needs at that width, on all four hosts; `lines={1}` cuts it to
one line with an ellipsis and `lines={2}` caps it there. A button does not
wrap. A stretched child is measured at the width it will get, so a shape or a
wrapping label inside a column answers for its real box.

**An element's own place.** `align` on a container is the default for its
children; `align_self` is the element's own cross-axis place in the run around
it, for a `<VStack>` that wants to sit in the centre of its parent.

**A size bound comes one side at a time as well.** `width={n}` pins both
bounds; `min_width`, `max_width`, `min_height` and `max_height` set one, in
source order, so `width={150} max_width={200}` may stretch to 200 and the
reverse order is pinned at 150. A range that ends up reversed — a minimum
above a maximum — is refused naming both numbers, because the solver would
otherwise fold them together silently.

**A grid whose columns follow the room.** `<Grid>` could only ever be one
column: `Track.fixed`, `Track.auto` and `Track.fraction` were in the engine
from the start and markup could name none of them. `columns` names them, and
`column_gap` and `row_gap` are the gaps:

```
<Grid columns="160 1fr auto" column_gap={10} row_gap={10}> ... </Grid>
```

160 points, then a share of what is left, then as wide as the widest child in
it. The other spelling is the one that removes a breakpoint rather than
writing one:

```
<Grid min_column={160} max_column={260} justify="center" column_gap={10}> ... </Grid>
```

As many equal columns as fit, each at least 160 wide and at most 260 — the
web's `repeat(auto-fit, minmax(160px, 260px))`, worked out in the layout pass
where the room is known.

**`auto-fit`, and the `fit` is the point.** A column nobody fills is collapsed,
not left empty: five tiles in a window with room for eleven columns are five
columns, not five tiles huddled at the left with six empty tracks beside them.
That is the whole difference between the web's `auto-fit` and its `auto-fill`,
and it is the bug this shipped with for exactly one afternoon.

A ceiling leaves room over, and `justify` says where a row sits in it — all six
spellings, per row, so a short last row is placed by what is actually in it
rather than by what a full row would have been. `examples/gradients` puts its
shelf of five gradients on one of these: five tiles to a line, then three and
two, then one, with no size written anywhere but that 160 and 260. Writing
`columns` and `min_column` on one grid is refused as deciding the columns
twice, and so is a `max_column` under the `min_column`.

**A size named by the job it does.** `font_role="body"`, `"heading"` or
`"caption"` is the platform's own size for that role — which follows the
reader's text-size setting, and a number cannot. `font_role` and `font_size`
land on the same property, so the last one written wins, the way `padding` and
`padding_x` do. `mono` is refused: it is body's size in a monospaced family,
and a family is not a property a control carries, so it would set nothing.

**A share of the room, and a shape.** `width_percent={50}` and
`height_percent={50}` are a share, 0 to 100, of the room the container offers
the child — its content box, less the child's own margin, so `width_percent={100}`
inside `margin_x={10}` fills the room between the margins rather than
overflowing it. Across a run it is the size, stretch or no stretch; along a
flexing run it is the basis, and `grow` still grows from it; `min_width` and
`max_width` still clamp it. A share and a pin on one axis are refused as
deciding it twice, and a share and a `basis` along one axis are refused by
the solver. `aspect_ratio={1.5}` is width over height, resolved at measure
from whichever axis is settled — a pinned width, a pinned height, a share, or
the stretch of the run it sits in — and from the measured width when none is.
A canvas that follows the window is one line:

```
<Canvas width_percent={100} aspect_ratio={1.777} />
```

### A screen laid out by coordinate

`<Box>` is `AbsoluteLayout` in markup: layers in one box, each placed by the
insets it carries. Per axis, a child with no opinion fills the box; `x` or
`y` places its measured size against the near edge and `right` or `bottom`
against the far one; two opposite insets stretch it between them; a `width`,
a `height` or a share sits where its inset says. A margin is honoured. It is
what an overlay is — a gradient behind a screen, a legend pinned to an edge, a
toast at the top — and there is nothing for a run to compute in any of those.

```
<Box>
  <MeshGradient color_1="#EAF4FC" color_2="#1E50A2" />        <!-- fills -->
  <VStack right={0} y={0} bottom={0} justify="center">        <!-- pinned right, full height -->
    <Swatch name="MOON WHITE" hex="#EAF4FC" />
  </VStack>
  <Label bottom={12} width={200} text="a caption at the foot" />
</Box>
```

**`x`, `y`, `right` and `bottom` are refused anywhere else**, in the sentence
`grow` already gets in a container that does not run its children: a
coordinate written inside a `<VStack>` would otherwise be a silent no-op, which
is the failure this library refuses everywhere. The refusal names `<Box>`. So
is `align` on a layer, because a layer is placed by its insets; and an inset
beside its opposite and a size on the same axis, which decides it three times.

**A component tag carries them too**, as placements. A component renders into
a builder of its own, so its root has no parent at the moment anything is
written on it; `<Swatch x={640} y={96} />` is written by the screen, applied to
the chip's root once it has rendered, and checked against the container the
tag sits in. Before that a component had to declare `x` and `y` as parameters
and forward them to its root — every shader canvas carried a `height` and a
`grow` field for no other reason — and `<ShaderCanvas grow={1} />` inside a
`<VStack>` was refused for sitting in a run that does not flex, while sitting in
one that does.

`examples/gradients` is the screen: a `<MeshGradient>` behind everything and
the other five on a shelf along the bottom, with a title, a toast and four
colour chips over them as ordinary native controls. Six shaders on one screen,
and not a line of shader in the file — **and not a coordinate or a sum
either.** It is two full-bleed layers in a `<Box>`, sized with `width_percent`;
the title is `self.cw(10, 28, 64)`, a tenth of its own box; the shelf is a
`<Grid min_column={160} max_column={260} justify="center">` that goes five
tiles to a line, then three and two, then one, centred in whatever it does not
use; and the colour chips are a third full-bleed layer in the `<Box>`, pinned
to the right edge, so the title stays on the centre of the window rather than
on the centre of the room left over beside them.
`--dump`, `--dump-narrow` and `--dump-tight` record it at three window sizes:
two would show the layout changing and three show it changing twice, which is
what a share with a floor and a ceiling needs. The frame rate under the title
is counted, not estimated: frames the background canvas actually put on screen
between two readings of the clock, divided by the seconds between them.

### A clock does not tick for a surface nobody is being shown

A frame drives drawing, and drawing into a surface the window server is not
showing is a full GPU pass that nobody sees. `CVDisplayLink` belongs to the
**display**, not to the window, so it keeps firing for a window that is
minimised, hidden or entirely covered — and `examples/gradients` has six
canvases riding it. Before this, that example held WindowServer at two to
three times its idle cost while its window was buried behind whatever you were
actually working in, which is the whole machine going slow, not one app.

So the tick is gated on what the window server says it is showing:
`occlusionState` on macOS, `IsWindowVisible` and `IsIconic` on Win32, the
window's own `hidden` on iOS. GTK4 needed nothing — a
`gtk_widget_add_tick_callback` only runs while its widget is on screen, which
is the behaviour the other three now have.

**Time is not stopped, only the drawing.** A window that comes back has
skipped the frames, not the seconds: `elapsed` is still measured from the
start, so an animation resumes where real time has got to rather than where it
was paused. That is a decision rather than a default — the other reading, in
which a hidden window's animation freezes and resumes, is equally defensible
and is what the frame *count* would suggest.

**Headless is exempt**, because it has no window server: nothing there is ever
being shown, and its frames are the program's to drive. `tests/frames.b` is
built on exactly that and fails if the exemption goes.

### Asking a display for a frame rate

On macOS 14 and later a surface with a window on a screen rides
`-[NSView displayLinkWithTarget:selector:]` rather than `CVDisplayLink`. The
rate then follows the screen the window is actually *on* — the old link was
bound to the active displays and never re-bound when a window moved — and the
link carries a `preferredFrameRateRange`, which is the only way to ask a
variable-rate display for 120 rather than accept whatever it settles on.

```beans
clock.prefer(0.0, 0.0, 0.0)        // as fast as this display goes
clock.prefer(60.0, 60.0, 60.0)     // sixty, held
```

A clock asks for the screen's own `maximumFramesPerSecond` until it is told
otherwise, so a cortado program is already asking for 120 on a display that
has it. Measured on a 60 Hz panel: 60.0 by default, and 30.0 after asking for
thirty.

**A range is permission, not a hint.** Asking for 60 with a floor of 30 was
measured holding a steady 42 — the system took the room it was given. Pass one
number three times for a constant rate, which is what an animation that
integrates its own time wants.

**Headless keeps `CVDisplayLink`, and that is load-bearing.** An `NSWindow`
that was never ordered front still answers a `screen`, so a view link is made
and then never fires; `tests/frames.b` went from five frames to none on the
first attempt at this. Which link a surface gets is decided on the app's role,
the same discriminator the visibility gate uses.

**Where the platform has no rate to set, the host paces itself.** Win32, whose
clock is a timer, turns the wanted rate into the timer's period. GTK4 has no
call at all — a `GdkFrameClock` is the display's — so it keeps the wish and
drops the ticks in between, and so does macOS on the `CVDisplayLink` fallback.
`prefer` therefore answers `allowed` on every host, and every host means it.
Asking for more than the display gives is still only a request anywhere.

`tests/frames.b` is where that is checked against a real display: five frames
asked for at twenty a second must take at least a fifth of a second, which is
three times what they take unpaced. GTK4's pacing is the one path the gate
cannot reach — a tick callback needs a mapped widget, and nothing in this
suite is ever on screen.

### Dressing a control

A control can be given a background, rounded corners and a border without
ceasing to be the platform's own control:

```beans
card.set_background(widgets.Rgba { red: 245, green: 245, blue: 247, alpha: 255 })?
card.set_corner_radius(10.0)?
card.set_border(1.0, widgets.Rgba { red: 0, green: 0, blue: 0, alpha: 30 })?
```

From markup, the same four names are attributes:

```
<Button background="#2f6f4f" corner_radius={6}
        border_width={1} border_color="#00000040">Order</Button>
```

**And the text's own colour, which is `text_color`.** Without it `background`
was half a property: a program could put a pale colour behind a label and had
no way to stop the system drawing white text on it, so a light card on a
dark-mode machine was unreadable and nothing in the API said why.

```
<Label background="#ffffffe8" corner_radius={15} text_color="#1b1b20">LAPIS</Label>
```

**Five controls carry it, and everything else is refused by name:** a label and
the four you type into — the same five that carry `alignment`, and for the same
reason. Each is a plain text view on all four hosts, so one name means one
call. A button, a check box and a radio button draw their words as a *title*
inside the platform's own bezel — an attributed string on AppKit, a CSS rule on
GTK, an owner-draw on Win32 — so one name would be three mechanisms, and a
link's colour is the system's on all four. `examples/gradients` is the screen
that needed this: its toast is dark precisely because the buttons in it are not
something `text_color` reaches.

A colour is a word in markup and a packed integer by the time it reaches the
ABI, parsed in one place, so `#abc` means the same thing in a control as it
does in a shader. `<TextField background="#f00" />` is refused where it is
written.

**A colour can be computed.** `background={self.tint}` is a Beans expression
like any other, because a colour is not a closed set of words. The two
attributes that *are* a closed set — `align` and `justify` — still need a
literal, so a misspelling is refused where it is written rather than reaching
the builder at run time.

**A property the platform has not got does not break the screen.** It is
stepped over, the way a canvas still renders where there is no GPU; every other
refusal still stops the render, because it is about the program.

**A push button takes a background.** That is the surprise, and it was settled
by looking at a screen rather than by reasoning: `examples/styled.b` puts every
control on a window twice, plain on the left and dressed on the right, and a
bezelled `NSButton` shows the colour, keeps its bezel's shape and draws its
title on top. So do the check box, slider, progress bar, switch, stepper,
separator, combo box and group box. Three offscreen probes had each given a
different answer, because a control rendered outside a window does not draw its
chrome.

**Four controls refuse a background, and they are refused by name.**
`TextField`, `SecureField`, `SearchField` and `TextArea` have an opaque bezel
drawn over anything behind them. The one that shows this is about the bezel and
not the class is `Label` — also an `NSTextField`, no bezel, takes a background
fine. Making those four show a colour means taking the bezel off, and then it
is not the platform's text field any more, which is the substitution cortado
exists to refuse. Corner radius and border have no such rule: every control
takes both.

These are properties rather than entry points, so no host gained a symbol for
them, and the layer they need is created on the first one that arrives rather
than on every control in the window. `Capability.layer_style` answers whether
the platform does any of it; today macOS does, and iOS, GTK4 and Win32 say
`unsupported` — a `UIView` has every one of these properties and GTK4 has a CSS
box, so what would remove that is the cases, not a redesign.

## Trees

**A table asks "what is at row 7"; an outline asks about a node.** That one
difference is the whole control, and it is why an outline is not a table with
indentation:

```beans
var tree: widgets.OutlineView = widgets.OutlineView.of(["Name"])?
tree.set_source(catalogue)?    // four methods: child_count, child_at, expandable, cell
tree.expand(connection)?
```

The control owns which nodes are showing, so opening one costs the children of
*that node* and nothing else. `tests/outline.b` opens one node of a tree with
400,004 nodes in it and asserts the source was asked fewer than a thousand
questions — a claim a flattened list cannot make, because a flattened list has
to know how long it is.

A **node** is an `int` the program chooses: a row id, an index into its own
list, anything. cortado never looks inside one. `OutlineView.root()` is the
node above the top level, and because it is never itself a row it doubles as
"nothing is selected". A `selection` event carries the **node**, not a row —
a row number changes every time something above it opens, and a node does not.

`expandable` is asked separately from `child_count`, and the difference is
load-bearing: a folder nobody has read yet has no children to report and must
still draw a twisty, and a table in a database has none and must not. A
control that inferred one from the other would make "empty" and "closed" the
same thing.

**Two platform gaps, both stated rather than papered over.** UIKit has no
outline view — a phone's tree is a collection-view layout with section
snapshots, which is a different control with a different data source — so the
kind answers `available() == false` there. And a `SysTreeView32` has no
columns at all, so a second column on Windows is `unsupported`; a program that
wants to work there asks for one and puts the rest in the text, which is what
a Windows tree looks like anyway.

## Icons

**An icon is named by what it is for, not by what it is called.** Every
platform ships an icon set and no two agree on a name: macOS and iOS have SF
Symbols (`arrow.clockwise`), GTK the freedesktop theme
(`view-refresh-symbolic`), Windows the standard toolbar bitmap and the shell's
stock icons (`STD_FILEOPEN`, `SIID_FOLDER`). So cortado names the job.

```beans
commands.set_icon(RUN, widgets.SystemIcon.run)      // on a command, and so on a toolbar
button.set_icon(widgets.SystemIcon.refresh)          // on a button
widgets.ImageView.of(widgets.SystemIcon.warning)?    // on its own
```

Twenty-seven roles — refresh, add, remove, delete, open, save, search, run,
stop, back, forward, cut, copy, paste, undo, redo, print, settings, info,
warning, error, help, document, folder, database, table, and `none` to take
one away. The point of using the system's set rather than shipping pictures is
that the person already knows their own system's icon for "refresh"; one this
library drew would be one more thing to learn.

**Not every role exists everywhere, and the API says so rather than drawing a
blank.** Windows' standard toolbar bitmap has fifteen images and no "run" or
"database" among them, so `SystemIcon.run.available()` is false there and
`set_icon` refuses rather than leaving an empty square. A program asks first
and shows a word instead — which is what `examples/cask` does, so its toolbar
is icons on a Mac and words on Windows without saying so twice.

`SystemIcon.platform_name()` answers what this host calls the role. It is for
reading: it is what makes a mapping table testable — `tests/icons.b` asserts
every role a host claims has its own name and that no two share one — and what
makes a misdrawn toolbar diagnosable without a screenshot. Nothing portable
should compare those strings.

## Menus, dialogs and the system

**A command is declared on the method it runs.** `@command` is read by
`cortado_app.run_main`, which builds the menu, puts it in the toolbar where the
platform has one, and routes the platform's event back to the method:

```beans
@command(title: "Execute", key: "mod+return", icon: "run")
pub fn run_statement() { self.work.execute() }

@command(title: "Connection", key: "mod+i", icon: "info", separator: true)
pub fn show_connection() { self.work.show_facts() }
```

`examples/cask` wrote that table twice before — five `Menu.add` rows with a
token apiece, and a router handler matching those tokens back to these four
calls. Two tables for one fact is a fact that goes out of step.

Four things are refused rather than ignored, because each is a silent no-op
otherwise: a **role the platform handles itself** (a method declared for `copy`
would never run — that command reaches the focused control through the
responder chain), an **icon name no role spells**, **two commands with one id**,
and a **command that declares a parameter**, which the platform has nothing to
fill. An icon this *platform* does not have is not one of them: the command
keeps its words, which is what `examples/cask`'s toolbar does on Windows.

**A command is not a control, which is why it is not in the markup.** It has a
role the platform places it by, a shortcut the platform spells, and an icon the
platform may not have — none of which is a shape on a screen.

**A role carries the platform's own words and keys.** This is the one idea that
makes a menu portable, and it is what `role:` above selects:

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

**Many things can move on one surface.** The platform gives a surface one
display link and refuses a second, which is right — a `CVDisplayLink` belongs
to a display, and a window that opened one per moving control would open a
dozen. So the fan-out lives above it: every `FrameClock` on a surface joins one
host clock, is delivered in the order it joined, and is told its own token
rather than the host's. Two `<ShaderCanvas>` on one screen both animate.
Nothing in a host changed for this.

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

### Six gradients, and not a line of shader in any of them

An `effect=` is one shape and two colours. A background usually wants more than
that, and writing it by hand means writing MSL — which works on Metal and
nowhere else, forever. So the six shapes worth naming are named:

```xml
<MeshGradient grow={1} lobe={2}
              color_1="#EAF4FC" reach_1={18}
              color_2="#1E50A2" reach_2={12}
              color_3="#F09199" reach_3={10}
              color_4="#895B8A" reach_4={11} />

<AuroraGradient  grow={1} bands={3} drop={1.2} />
<FlowGradient    grow={1} color="#1B3365" color_to="#53B0C7" highlight="#F5E3C2" />
<PrismGradient   grow={1} angle={35} spread={0.62} saturation={0.8} />
<GlowGradient    grow={1} orbs={2} radius={1.2} pulse={0.5} />
<SkyGradient     grow={1} zenith="#2D5FC6" horizon="#F2D1B4" sun_height={0.3} />
```

```beans
import {MeshGradient, AuroraGradient, FlowGradient,
        PrismGradient, GlowGradient, SkyGradient} from cortado.gpu
```

Every one takes `speed` and `grain` as multiples of its own pace, and `height`
or `grow` like any canvas. `speed={0}` holds a gradient still, which is a
legitimate thing to ask a background for.

**Why this is a class and not six more `effect=` names.** `Effect` writes MSL
directly, in one string, and its signature is two colours and three numbers —
there is no room in it for four colour stops with a reach each. A `Gradient`
writes its body through a `ShaderDialect` instead, and never names a type or a
built-in itself.

**That is the whole portability story, and it is deliberately small.** MSL,
HLSL and GLSL disagree about a handful of spellings for this kind of shader:
`float3` against `vec3`, `fract` against `frac`, `mix` against `lerp`. A
dialect is that table. Landing Windows or Linux is a row in `ShaderDialect.of`,
a branch in `ShaderCanvas.wrap_in`, and one more entry in
`ShaderCanvas.languages` — and not one character of any markup above, because
no screen ever wrote the shader down.

**Where it stops today, said plainly.** `ShaderCanvas.languages()` answers
`msl` and nothing else, so a host that accepted only HLSL would be refused by
name, before a driver ever saw a program written for the wrong compiler. The
missing half is not the arithmetic — it is the whole-program wrapper: the
vertex stage, the uniform struct, and the entry points. `tests/named_gradients.b`
holds the seam to its shape, so the day a second language lands, the three
lines that have to change are the ones that say so.

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

### A shape, with no shader in it

`<ShapeCanvas>` is the other half of `<ShaderCanvas>`: the shapes people
actually want, without writing a line of Metal.

```
<ShapeCanvas height={44} figure="rounded_rect" radius={10} inset={6}
             fill="gradient" color="#4088bf" color_to="#0d1b2a"
             stroke="#8fb7d4" stroke_width={1} />
```

**Four figures, not seven.** `rounded_rect`, `ellipse`, `ring` and `capsule` —
because a rectangle is a rounded rect with radius 0, a circle is an ellipse with
equal halves, and a border is a stroke. Naming those separately would be four
ways to write two things.

**The fill is an `Effect`, unchanged.** A shape is a mask and an effect is a
material, and masks and materials multiply: `solid`, `gradient`, `ripple`,
`checker` and the rest each work with each figure, because the effect's body is
hoisted into a function and called rather than replaced. Putting shapes into
the effect enum instead would have meant 13 names for 6 × 4 combinations, and
no way at all to say "a circle with a gradient in it".

**The edge is a fixed one-pixel ramp, deliberately not `fwidth`.** The textbook
signed-distance antialias divides by a screen-space derivative, which the
hardware computes per quad — so the width of the blended band is the GPU's
business, and a boundary pixel is not the same byte on two devices. That is
exactly the property `tests/triangle.out` exists to hold. With a fixed ramp an
edge landing on a pixel boundary gives coverage exactly 1 on one side and
exactly 0 on the other, so `tests/shapes.b` can assert that a rectangle has
16 fill pixels, 48 background and **zero** part-covered — and the same code
still antialiases a circle properly, with no mode to switch.

**A shape knows where it is on screen.** `radius={12}` is 12 points on every
display, which needed the backing scale to reach the shader: the drawable's
size is in pixels and everything the program writes is in points, so on a
Retina screen the two disagree by a factor of two. It rides the fourth uniform,
which was reserved for something like this.

### A canvas a person can use

A canvas already hears a pointer — the hit test finds it like any other view,
and `event.position` arrives in the control's own points, top-left and y down.
Three things were missing, and are there now.

```beans
plot.set_focusable(true)?                        // and it joins the tab order
plot.set_a11y_role(widgets.A11yRole.button)?     // and says what it is
plot.set_a11y_label("Sales, last twelve months")?
let uv: geometry.Point = gpu.uv_of(plot.handle(), event.position)?
```

**Focus is asked for, not assumed.** A decorative canvas must stay out of the
tab order, so `set_focusable` is off by default and `focus()` on a canvas that
has not asked says `wrong_moment` — this platform can, and you have not asked —
rather than `unsupported`, which is a different fact about a different thing.

**A canvas may claim a role that already exists** — `button`, `image` or
`group` — and not invent one, because a word no screen reader knows is worse
than the truthful `group`. It is set on the view rather than only remembered,
since a role cortado prints in a golden and a role VoiceOver says out loud are
different things. Both keys are the canvas's alone: for every other control,
"can it take the keyboard" and "what is it" are the platform's answers.

**An accessibility label is carried by every control**, because a toolbar of
icons is unusable without one. Reading it back answers **what a screen reader
will say**, not what cortado was told: an unnamed button is announced by its
own title, and `""` means genuinely silent.

**`gpu.uv_of` is the conversion, written once.** A pointer's position divided
by the canvas's size in points is exactly the `uv` the shader was given — no
flip, because `quad_corners` already does it in the vertex data, and no scale,
because the 2× lives only inside `size`. It is a division and nothing else, and
it exists so that nobody re-derives it and gets the flip wrong.

**Hit-testing what the GPU drew has one honest answer.** Reading the pixel back
is a round trip to a drawable the compositor owns, per click. Guessing is
worse. With `<ShapeCanvas>` the program *described* the geometry, so the same
signed distance can be evaluated in Beans from the same parameters that
generated the shader — two implementations of one rule, which is only
trustworthy because `tests/shapes.b` checks them against each other pixel by
pixel. A `<ShaderCanvas shader={...}>` has no such thing and cannot.

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

## Permission

macOS does not refuse a program that touches a privacy-gated framework without
a usage description. It **ends the process** — on a later turn of the run loop,
in unrelated code, with nothing on stderr:

```
termination namespace TCC: "This app has crashed because it attempted to
access privacy-sensitive data without a usage description."
```

There is no status to turn into a `Result`, because there is no process left to
answer. So the whole of `cortado.device` is built on one rule: **never touch the
framework to answer a question about it.**

```beans
match device.Permission.camera.status()? {
    granted => { open_the_camera()? }
    undecided => { device.Permission.camera.request(1)? }
    denied => { explain_why_not() }
    unavailable => { hide_the_feature() }
}
```

Reading a status touches nothing. The host reads the Info.plist usage
description the program declared and the framework's own *static* query —
`[CBCentralManager authorization]`, `[AVCaptureDevice
authorizationStatusForMediaType:]`, `[CLLocationManager authorizationStatus]`,
`CGPreflightScreenCaptureAccess` — all of which are class methods that construct
nothing. Constructing the manager or starting the session is what kills you,
and cortado does neither until the service that needs it is asked for.

**`unavailable` is what an unbundled program always gets, and that is not
caution.** A bare binary has no privacy identity, so the system answers for
whichever process is *responsible* for it. A probe read `microphone:
authorized` from a program with no usage description of any kind, because
Terminal.app holds that grant — and passing that number on would have been
worse than passing nothing. Under `beansc run` the process is `beansc`, so this
is always what the interpreter leg sees.

**And `request` refuses rather than prompting** where a prompt cannot appear:
no bundle, or no usage description. That refusal *is* the feature — asking
without one is the death above, and the worst that happens now is a message.

`tools/bundle.sh` writes the keys:

```bash
tools/bundle.sh build/app MyApp com.example.myapp '' \
    NSCameraUsageDescription='to scan a receipt'
```

Proven on a real machine, three states in order: unbundled → `unavailable` and
the request refused; bundled with the sentence → `undecided` and a prompt;
after the user answers → `granted`. `tests/permission.out` is the first of
those, and it is the same bytes on every host — because the shape of the
contract is portable even where the answers are not.

## Why it stays smooth

Four claims, each with a test behind it rather than an adjective.

**One change makes one edit.** `tests/diff.out` is the reconciler's arithmetic
written down: a render where the text changed prints `set root text="after"`,
and a render where nothing changed prints `(nothing changed)`. Not "few edits"
— the exact list, as a golden, on every host. A reconciler that rebuilt a
subtree to change a label would print a different file.

**A hundred times the rows is not a hundred times the work.** A table asks for
the cells it is about to draw and holds none, so `tests/table.out` can build one
of 1,000 rows and one of 100,000 and assert the second asked for no more cells
than the first. `examples/ledger.b` is fifty thousand rows in a window that
opens instantly, and the rows in it do not exist — every cell is arithmetic,
computed when something is about to draw it.

**No Beans code runs per animation frame.** An animation is *described* in
Beans and *executed* by the platform: on macOS and iOS a `CABasicAnimation`
runs on the render server, which keeps going at the display's rate while the
main thread is busy. `tests/anim.out` is the same bytes through Core Animation
and through the fallback that walks the curve itself, which is the strongest
thing the suite says — two completely different executions of one description.

**The frame clock is the display's, not a timer's.** `CVDisplayLink` on macOS,
`CADisplayLink` on iOS, `gtk_widget_add_tick_callback` on GTK. A timer at
1/60 of a second is a guess that is wrong on every 120 Hz screen and drifts on
all of them; `tests/clock.out` checks the numbering and the elapsed time, and
it can run headless because the host can raise a frame on demand.

What cortado does **not** claim: that it is faster than the platform. Every
control here is the platform's own, drawn by the platform's own code. The work
cortado can add is the work between the program and that control, and the four
files above are where that work is counted.

## Shipping

```
cortado publish              # a Release build, wrapped and signed
open build/release/Myapp.app
```

The name, the identifier, the version, the icon and every usage description
come from `cortado.pot`, and each declared key is read back out of the finished
bundle with `plutil -extract` — the way macOS reads it. Not "the file contains
it" and not "the file lints": the first version of this wrote the usage
descriptions after `</plist>`, `plutil -lint` called the file OK because a
plist parser stops at the closing tag, the app launched, and every usage
description was silently missing.

`tools/bundle.sh build/gallery Gallery com.example.gallery` still wraps a loose
binary that is not a project, and calls the same code.

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
