// A page, really loaded, really parsed, really answering.
//
// `tests/web.out` is the portable half of the web view's contract: which calls
// refuse, what a fresh one knows, what every other kind says. This is the
// other half, and it cannot be portable — whether an engine runs a page in a
// window-less process is a property of the run rather than of cortado.
// WKWebView does it on a Mac; the iOS Simulator starts no web content process
// for an application with no scene on screen. So this file runs where a page
// can load and says so where one cannot, and it is not in `cross_host`.
//
// What it proves is the part a mock could not: the markup went into a real
// engine, the engine parsed it, the title came back out, a script ran inside
// it and answered, and a page that was invited reached the program.
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.events
import std.io

const ASK_TITLE: int = 77
const ASK_BROKEN: int = 78

class Heard {
    pub started: int = 0
    pub finished: int = 0
    pub failed: int = 0
    pub results: int = 0
    pub messages: int = 0
    pub said: string = ""
    pub answered: string = ""
    pub broke: string = ""
    pub fn init() {}
}

/// The page. A raw string, because markup is full of braces — and a raw string
/// ends at the first `"`, so every quote inside is a single one.
fn markup() -> string {
    return r"<!doctype html>
<meta charset='utf-8'>
<title>Cortado</title>
<body>
<script>
  var post = window.webkit && window.webkit.messageHandlers.gate;
  if (post) post.postMessage('the page says hello');
</script>
"
}

fn drive() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.headless)
    app.check_abi()?
    var window: surface.Window = app.window(400.0, 300.0, "Page")?
    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?
    let tally: Heard = new Heard()

    if !widgets.WebView.offered() {
        io.println("-- a page --")
        io.println("  this platform has no browser engine: true")
        app.shutdown()
        return ok(true)
    }

    var view: widgets.WebView = widgets.WebView.of()?
    root.add(view)?
    // The invitation. Without it the script below posts into nothing.
    view.listen("gate")?

    app.router.on(view.handle(), events.EventKind.web_started,
        fn(event: events.UiEvent) { tally.started = tally.started + 1 })
    app.router.on(view.handle(), events.EventKind.web_finished,
        fn(event: events.UiEvent) { tally.finished = tally.finished + 1 })
    app.router.on(view.handle(), events.EventKind.web_failed,
        fn(event: events.UiEvent) { tally.failed = tally.failed + 1 })
    app.router.on(view.handle(), events.EventKind.web_message,
        fn(event: events.UiEvent) {
            tally.messages = tally.messages + 1
            match view.collect(event.token) {
                ok(words) => { tally.said = words }
                err(problem) => { tally.said = problem.kind }
            }
        })
    app.router.on(view.handle(), events.EventKind.web_result,
        fn(event: events.UiEvent) {
            tally.results = tally.results + 1
            match view.collect(event.token) {
                ok(words) => {
                    if event.token == ASK_TITLE { tally.answered = words }
                    if event.token == ASK_BROKEN { tally.broke = words }
                }
                err(problem) => {}
            }
        })

    // Markup handed straight to the engine: no server, no network.
    view.load_html(markup(), "")?
    // A bounded turn of the run loop, which is how a headless gate sees an
    // asynchronous answer without waiting on a real one.
    app.run_for(2.0)?

    io.println("-- a page --")
    io.println("  it started and finished and did not fail: {tally.started == 1 && tally.finished == 1 && tally.failed == 0}")
    io.println("  the engine parsed the markup: {view.title()? == "Cortado"}")

    // A page that was invited reached the program, and brought its words.
    io.println("  a page that was invited reached the program: {tally.messages == 1}")
    io.println("  and brought what it said: {tally.said == "the page says hello"}")

    // A script runs inside the page it was loaded into, and its answer comes
    // back under the caller's own token.
    view.eval("document.title + '!'", ASK_TITLE)?
    app.run_for(2.0)?
    io.println("  a script runs in the page and answers: {tally.answered == "Cortado!"}")

    // A script that throws answers too, rather than going quiet. `index` is 1
    // for a failure, which is what tells the two apart.
    view.eval("nothing.at.all", ASK_BROKEN)?
    app.run_for(2.0)?
    io.println("  and a script that throws answers as well: {tally.results == 2 && tally.broke != ""}")

    // Collected once and then gone.
    io.println("  what was collected is gone: {view.collect(ASK_TITLE)? == ""}")

    // Loading is a navigation, so it is one more of each.
    view.load_html(markup(), "")?
    app.run_for(2.0)?
    io.println("  a second load is a second navigation: {tally.started == 2 && tally.finished == 2}")

    app.router.forget(view.handle())
    window.close()?
    app.shutdown()
    return ok(true)
}

fn main() {
    match drive() {
        ok(done) => { io.println("drove={done}") }
        err(problem) => { io.println("{problem.kind}: {problem.msg}") }
    }
}
