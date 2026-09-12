// A browser engine in a rectangle.
//
// The one control in cortado that is a whole other system, and the one with
// the widest platform gap: WKWebView is part of macOS and iOS, GTK's engine is
// a separate library and Windows' is a redistributable. So everything below
// prints agreement rather than inventory — the same bytes come out of a
// platform with an engine and one without, because each line says "this is
// true wherever there is one, and there is nothing to be untrue where there is
// not".
//
// **Nothing here loads a page**, and that is two decisions rather than one.
// A headless gate has no network and should not want one: a test that fetched
// a real URL would be a test of somebody else's server. And whether an engine
// will run a page at all in a window-less process is a property of the *run* —
// the iOS Simulator starts no web content process for an application with no
// scene on screen — so a line about it would make this golden a description of
// the machine rather than of the contract.
//
// What is checked here is the part that is cortado's: which calls refuse and
// why, what a fresh view knows about itself, and that every other kind refuses
// a web call by kind. `tests/page.b` is where a page is really loaded, and it
// runs on the hosts where one can be.
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.component
import cortado.host
import cortado.events
import std.io

class Heard {
    pub started: int = 0
    pub finished: int = 0
    pub failed: int = 0
    pub results: int = 0
    pub last: int = 0
    pub fn init() {}
}

fn refusal_load(view: widgets.WebView, url: string) -> string {
    match view.load(url) {
        ok(done) => { return "" }
        err(problem) => { return problem.kind }
    }
}

fn drive() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.headless)
    app.check_abi()?
    var window: surface.Window = app.window(400.0, 300.0, "Web")?
    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?
    let tally: Heard = new Heard()

    let here: bool = widgets.WebView.offered()

    // The capability and the kind are two ways of asking one question, and
    // they must not answer differently — a program that laid out one screen
    // from the capability and built controls from the kind would build a
    // control it had decided not to show.
    io.println("-- a web view --")
    io.println("  the capability and the kind agree: {here == widgets.WidgetKind.web_view.available()}")

    var fresh_ok: bool = true
    var refuse_ok: bool = true
    var collect_ok: bool = true
    var history_ok: bool = true

    if here {
        var view: widgets.WebView = widgets.WebView.of()?
        root.add(view)?

        // A fresh one is nowhere and has been nowhere.
        fresh_ok = view.url()? == "" && !view.can_go_back()? && !view.can_go_forward()?

        // A string no URL parser accepts is the caller's bug. Answering
        // "loading" to it would make the failure arrive later as a navigation
        // error about a page nobody asked for.
        refuse_ok = refusal_load(view, "not a url at all") == "out_of_range" &&
                    refusal_load(view, "") == "out_of_range"

        // Nowhere to go back to is a refusal rather than a silent no-op: a
        // program that dimmed its own back button would never ask, and one
        // that did not has a bug worth hearing about.
        history_ok = refusal_go(view, true) == "out_of_range" &&
                     refusal_go(view, false) == "out_of_range"

        app.router.on(view.handle(), events.EventKind.web_started,
            fn(event: events.UiEvent) { tally.started = tally.started + 1 })
        app.router.on(view.handle(), events.EventKind.web_finished,
            fn(event: events.UiEvent) { tally.finished = tally.finished + 1 })
        app.router.on(view.handle(), events.EventKind.web_failed,
            fn(event: events.UiEvent) { tally.failed = tally.failed + 1 })
        app.router.on(view.handle(), events.EventKind.web_result,
            fn(event: events.UiEvent) {
                tally.results = tally.results + 1
                tally.last = event.token
            })

        // Nothing here loads a page. Whether an engine will run one in a
        // headless, window-less process is a property of the *run* and not of
        // cortado's contract — the iOS Simulator starts no web content process
        // for an application with no scene on screen — and a line that was
        // true on one platform and false on another would make this golden a
        // description of the machine. `tests/page.b` is where a page is
        // actually loaded, and it runs where one can be.
        collect_ok = view.collect(1)? == ""

        app.router.forget(view.handle())
    }

    io.println("  a fresh one is nowhere and has been nowhere: {fresh_ok}")
    io.println("  a string that is not a URL is refused: {refuse_ok}")
    io.println("  nowhere to go back to is refused, not ignored: {history_ok}")
    io.println("  a token nobody filled in collects nothing: {collect_ok}")

    // Every other kind refuses every web call, and a platform with no engine
    // refuses them for every handle there is. Both are the same line, which is
    // what makes this golden portable.
    var asked: int = 0
    var right: int = 0
    for kind: widgets.WidgetKind in widgets.WidgetKind.all() {
        if !kind.available() { continue }
        if kind == widgets.WidgetKind.web_view { continue }
        asked = asked + 1
        var control: widgets.Widget = component.WidgetMaker.of_kind(kind)?
        var borrowed: widgets.WebView = new widgets.WebView()
        // The call is made against the wrong kind through the raw handle,
        // because that is the shape a mistake takes: a handle that came from
        // somewhere else.
        if wrong_kind(control) == "wrong_widget" { right = right + 1 }
        else { io.println("  ...{kind.name()} answered '{wrong_kind(control)}' to a web call") }
    }
    io.println("  every other control refuses a web call by kind: {right == asked && asked > 0}")

    window.close()?
    app.shutdown()
    return ok(true)
}

/// What `ctd_web_url` says about a handle that is not a web view.
fn wrong_kind(control: widgets.Widget) -> string {
    unsafe {
        match host.HostText.read("read where a control is",
            fn(out: RawPtr<i8>, cap: i32) -> i32 {
                return host.ctd_web_url(control.handle().raw, out, cap)
            }) {
            ok(text) => { return "" }
            err(problem) => { return problem.kind }
        }
    }
}

fn refusal_go(view: widgets.WebView, back: bool) -> string {
    let answer: Result<bool> = if back { view.go_back() } else { view.go_forward() }
    match answer {
        ok(done) => { return "" }
        err(problem) => { return problem.kind }
    }
}

fn main() {
    match drive() {
        ok(done) => { io.println("drove={done}") }
        err(problem) => { io.println("{problem.kind}: {problem.msg}") }
    }
}
