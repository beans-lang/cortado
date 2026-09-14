// What the machine is doing, watched rather than polled.
//
//     beansc build examples/vitals.b -o build/vitals && ./build/vitals
//
// Four lines: what this computer can reach, what is running it, how full the
// battery is and how hot it is. They are **not on a timer.** Each one is
// redrawn when the system says the thing changed, which is the whole argument
// for asking the platform rather than reading a file every second: a program
// that polls is awake sixty times a minute to learn nothing, and on the
// machine it is reporting the battery of, that is the wrong thing to be.
//
// Unplug the laptop while this is open and the power line changes on its own.
// Turn the wifi off and the network line does.
//
// **Nothing here is privacy-gated**, which is what makes this example an
// ordinary program: no bundle, no usage description, no prompt. Every call was
// proven safe from a bare binary across a turn of the run loop, which is where
// a privacy death lands. That is why these two services came before the other
// six — `examples/permissions.b` is the other story, and it can only ever
// report that a program run from a terminal has no privacy identity of its own.
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

/// The four lines, so the handlers have one thing to write into.
class Panel {
    pub net: widgets.Label
    pub power: widgets.Label
    pub battery: widgets.Label
    pub heat: widgets.Label
    pub fn init(net: widgets.Label, power: widgets.Label,
                battery: widgets.Label, heat: widgets.Label) {
        self.net = net
        self.power = power
        self.battery = battery
        self.heat = heat
    }

    /// Everything about the network, in one line of English.
    pub fn say_network() {
        let path: device.NetworkPath = device.Machine.path().or(device.NetworkPath.unknown)
        if !path.reachable() {
            self.net.set_text("network: nothing to reach").or(false)
            return
        }
        var cost: string = ""
        if device.Machine.expensive().or(false) { cost = ", and it costs by the byte" }
        else if device.Machine.constrained().or(false) { cost = ", and it has been asked to use less" }
        self.net.set_text("network: over {path.name()}{cost}").or(false)
    }

    pub fn say_power() {
        let source: device.PowerSource = device.Machine.power().or(device.PowerSource.unknown)
        var saving: string = ""
        if device.Machine.saving().or(false) { saving = ", saving power" }
        self.power.set_text("power: {source.name()}{saving}").or(false)

        // A charge or nothing at all. A meter drawn full for a machine with no
        // battery is worse than no meter, which is why this refuses rather
        // than answering 1.
        match device.Machine.charge() {
            ok(level) => {
                let percent: int = (level * 100.0) as int
                self.battery.set_text("battery: {percent}%").or(false)
            }
            err(problem) => {
                self.battery.set_text("battery: this machine has none").or(false)
            }
        }
    }

    pub fn say_heat() {
        let heat: device.ThermalState = device.Machine.heat().or(device.ThermalState.unknown)
        if heat == device.ThermalState.unknown {
            // Two of the four platforms have no scale for this, and saying so
            // is better than drawing a gauge with nothing behind it.
            self.heat.set_text("heat: this platform has no scale for it").or(false)
            return
        }
        var advice: string = ""
        if heat.under_strain() { advice = " — a program should do less" }
        self.heat.set_text("heat: {heat.name()}{advice}").or(false)
    }
}

fn run() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.gui)
    app.check_abi()?

    var window: surface.Window = app.window(460.0, 220.0, "Vitals")?
    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?

    var title: widgets.Label = widgets.Label.of("What this machine is doing.")?
    var net: widgets.Label = widgets.Label.of("network: asking")?
    var power: widgets.Label = widgets.Label.of("power: asking")?
    var battery: widgets.Label = widgets.Label.of("battery: asking")?
    var heat: widgets.Label = widgets.Label.of("heat: asking")?
    root.add(title)?
    root.add(net)?
    root.add(power)?
    root.add(battery)?
    root.add(heat)?

    var sheet: widgets.WidgetLayout = new widgets.WidgetLayout()
    var body: layout.StackLayout = layout.StackLayout.column(10.0)
    body.set_padding(geometry.EdgeInsets.all(20.0))
    body.set_align(geometry.Align.stretch)
    var page: layout.LayoutNode = sheet.group("page", root, body)?
    page.add(sheet.leaf("title", title))
    page.add(sheet.leaf("net", net))
    page.add(sheet.leaf("power", power))
    page.add(sheet.leaf("battery", battery))
    page.add(sheet.leaf("heat", heat))
    var solver: layout.Solver = new layout.Solver(sheet)
    let content: geometry.Size = window.content_size()?
    solver.solve(page, geometry.Rect.at(geometry.Point.zero(), content))?
    sheet.apply(page)?

    let panel: Panel = new Panel(net, power, battery, heat)

    // Registering is what starts the platform's own monitor. There is no watch
    // call and no timer: a host learns that somebody wants a kind the moment
    // the first handler arrives, which is the same decision, and it stops
    // again when the last one goes.
    app.router.on(host.Handle.none(), events.EventKind.net_changed,
        fn(event: events.UiEvent) { panel.say_network() })
    app.router.on(host.Handle.none(), events.EventKind.power_changed,
        fn(event: events.UiEvent) {
            panel.say_power()
            panel.say_heat()
        })

    panel.say_power()
    panel.say_heat()
    panel.say_network()

    var dumping: bool = false
    for arg: string in os.args() {
        if arg == "--dump" { dumping = true }
    }
    if dumping {
        // The network answer is a push on two of the four platforms, so it
        // arrives a turn of the loop after the first ask. A program with a
        // window has that turn for free; a dump has to wait for it.
        app.run_for(0.3)?
        panel.say_network()
        io.println("{net.text().or("?")}")
        io.println("{power.text().or("?")}")
        io.println("{battery.text().or("?")}")
        io.println("{heat.text().or("?")}")
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
