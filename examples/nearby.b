// The four things a program has to ask permission for, and what asking looks
// like when nobody granted anything.
//
//     beansc build examples/nearby.b -o build/nearby && ./build/nearby
//
// **Run it like that and every line says the same thing: not allowed.** That
// is not the example failing — it is the example working, and it is the first
// thing anybody writing against these services needs to see. A program built
// as a bare binary has no privacy identity at all: macOS answers for whichever
// process is *responsible* for it, which is the terminal, whose grants are not
// this program's. So cortado refuses rather than reporting somebody else's.
//
// To see the other half, make it an application:
//
//     beansc build examples/nearby.b -o build/nearby
//     tools/bundle.sh build/nearby Nearby org.example.nearby "" \
//       NSBluetoothAlwaysUsageDescription="to list what is nearby" \
//       NSLocationWhenInUseUsageDescription="to show where this machine is" \
//       NSCameraUsageDescription="to list the cameras" \
//       NSMicrophoneUsageDescription="to list the microphones"
//     open build/Nearby.app
//
// Same program, same code path, and now each line reads what the system
// actually says — and the first time a service is really started, a panel
// appears asking the person, because that is what these permissions are.
//
// **The window never starts a service on its own.** Scanning for Bluetooth and
// watching where the machine is are things a person asks for, not things a
// program does because it was opened, and the buttons below are what asking
// looks like. A library that started a radio at launch would be a library that
// put a prompt on the screen before anybody pressed anything.
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.layout
import cortado.geometry
import cortado.device
import cortado.events
import cortado.host
import std.io
import std.os

/// What the screen is showing, so the handlers have one thing to write into.
class Sheet {
    pub place: widgets.Label
    pub radio: widgets.Label
    pub eyes: widgets.Label
    pub screen: widgets.Label
    pub fn init(place: widgets.Label, radio: widgets.Label,
                eyes: widgets.Label, screen: widgets.Label) {
        self.place = place
        self.radio = radio
        self.eyes = eyes
        self.screen = screen
    }

    /// One line for a service, saying either what it answered or why it could
    /// not. The `err` arm is the one most people will see first.
    pub fn say_place() {
        match device.Gated.where_now() {
            ok(here) => { self.place.set_text("where: {here.show()}").or(false) }
            err(problem) => {
                self.place.set_text("where: {problem.msg}").or(false)
            }
        }
    }

    pub fn say_radio() {
        let seen: int = device.Gated.nearby_count()
        if seen == 0 {
            self.radio.set_text("nearby: nothing seen yet").or(false)
            return
        }
        // The strongest signal is the nearest thing, which is the one a person
        // looking at a list cares about.
        var best: int = 0
        var strongest: f64 = -1000.0
        var at: int = 0
        for at < seen {
            let signal: f64 = device.Gated.nearby_signal(at).or(-1000.0)
            if signal > strongest { strongest = signal; best = at }
            at = at + 1
        }
        var called: string = device.Gated.nearby_name(best).or("")
        // Most peripherals advertise no name at all until they are connected,
        // so the identifier is what a person has to go on.
        if called == "" { called = device.Gated.nearby_id(best).or("something") }
        self.radio.set_text("nearby: {seen} seen, closest is {called} at {strongest as int} dBm").or(false)
    }

    pub fn say_eyes() {
        let cameras: int = device.Gated.capture_count(device.CaptureKind.camera)
        let microphones: int = device.Gated.capture_count(device.CaptureKind.microphone)
        if cameras == 0 && microphones == 0 {
            self.eyes.set_text("cameras and microphones: not allowed to look").or(false)
            return
        }
        var first: string = device.Gated.capture_name(device.CaptureKind.camera, 0).or("?")
        self.eyes.set_text("cameras: {cameras}, microphones: {microphones} — first is {first}").or(false)
    }

    pub fn say_screen() {
        let displays: int = device.Gated.screen_count()
        if displays == 0 {
            self.screen.set_text("screen: not allowed to record").or(false)
            return
        }
        match device.Gated.screen_size(0) {
            ok(size) => {
                let wide: int = size.width as int
                let tall: int = size.height as int
                self.screen.set_text("screen: {displays} display(s), the first is {wide} by {tall}").or(false)
            }
            err(problem) => { self.screen.set_text("screen: {problem.msg}").or(false) }
        }
    }

    pub fn say_all() {
        self.say_place()
        self.say_radio()
        self.say_eyes()
        self.say_screen()
    }
}

fn run() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.gui)
    app.check_abi()?

    var window: surface.Window = app.window(560.0, 280.0, "Nearby")?
    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?

    var title: widgets.Label = widgets.Label.of("Four things this program has to ask for.")?
    var place: widgets.Label = widgets.Label.of("where: not asked")?
    var radio: widgets.Label = widgets.Label.of("nearby: not asked")?
    var eyes: widgets.Label = widgets.Label.of("cameras and microphones: not asked")?
    var screen: widgets.Label = widgets.Label.of("screen: not asked")?
    var ask_place: widgets.Button = widgets.Button.of("Watch where this machine is")?
    var ask_radio: widgets.Button = widgets.Button.of("Scan for what is nearby")?
    // Added one at a time rather than through a list: a list literal takes the
    // type of its first element, and a Button is not a Label.
    root.add(title)?
    root.add(place)?
    root.add(radio)?
    root.add(eyes)?
    root.add(screen)?
    root.add(ask_place)?
    root.add(ask_radio)?

    var sheet: widgets.WidgetLayout = new widgets.WidgetLayout()
    var body: layout.StackLayout = layout.StackLayout.column(10.0)
    body.set_padding(geometry.EdgeInsets.all(20.0))
    body.set_align(geometry.Align.stretch)
    var page: layout.LayoutNode = sheet.group("page", root, body)
    page.add(sheet.leaf("title", title))
    page.add(sheet.leaf("place", place))
    page.add(sheet.leaf("radio", radio))
    page.add(sheet.leaf("eyes", eyes))
    page.add(sheet.leaf("screen", screen))
    page.add(sheet.leaf("ask_place", ask_place))
    page.add(sheet.leaf("ask_radio", ask_radio))
    var solver: layout.Solver = new layout.Solver(sheet)
    let content: geometry.Size = window.content_size()?
    solver.solve(page, geometry.Rect.at(geometry.Point.zero(), content))?
    sheet.apply(page)?

    let shown: Sheet = new Sheet(place, radio, eyes, screen)

    // Starting a service is a thing a person asks for. A library that started
    // a radio at launch would put a prompt on the screen before anybody
    // pressed anything, which is how an application earns a reputation.
    app.router.on(ask_place.handle(), events.EventKind.activate,
        fn(event: events.UiEvent) {
            match device.Gated.watch_place() {
                ok(started) => { shown.say_place() }
                err(problem) => { place.set_text("where: {problem.msg}").or(false) }
            }
        })
    app.router.on(ask_radio.handle(), events.EventKind.activate,
        fn(event: events.UiEvent) {
            match device.Gated.scan(true) {
                ok(started) => { shown.say_radio() }
                err(problem) => { radio.set_text("nearby: {problem.msg}").or(false) }
            }
        })

    // A fix and a peripheral both arrive when they arrive, which is why they
    // are events and not return values.
    app.router.on(host.Handle.none(), events.EventKind.location,
        fn(event: events.UiEvent) { shown.say_place() })
    app.router.on(host.Handle.none(), events.EventKind.ble_found,
        fn(event: events.UiEvent) { shown.say_radio() })

    shown.say_all()

    var dumping: bool = false
    for arg: string in os.args() {
        if arg == "--dump" { dumping = true }
    }
    if dumping {
        io.println("{place.text().or("?")}")
        io.println("{radio.text().or("?")}")
        io.println("{eyes.text().or("?")}")
        io.println("{screen.text().or("?")}")
        app.shutdown()
        return ok(true)
    }

    window.show()?
    app.run()
    app.shutdown()
    return ok(true)
}

fn main() {
    match run() {
        ok(done) => { io.println("done={done}") }
        err(problem) => { io.println("{problem.kind}: {problem.msg}") }
    }
}
