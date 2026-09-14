// A browser engine in a rectangle, and a page that can talk back.
//
//     beansc build examples/browser.b -o build/browser && ./build/browser
//
// A web view is the one control in cortado that is a whole other system. What
// this example is really about is the two rules that come with it:
//
// **Everything happens later.** A load finishes on a later turn of the run
// loop, as an event. So the address bar below is filled in from
// `web_finished`, never from the line that called `load` — which has not
// loaded anything yet when it returns.
//
// **A page cannot reach the program unless it is invited.** `listen` names a
// channel; a page that posts to an unnamed channel is ignored. A fresh web
// view is a viewer, not a bridge. The page loaded here posts to the channel
// this program opened, and the label at the bottom shows what arrived.
//
// **Not on every platform**, and this is the widest gap cortado has: WKWebView
// is part of macOS and iOS, GTK's engine is a separate library and Windows' is
// a redistributable. This example asks first and says so when the answer is
// no, because a grey rectangle that was going to be a browser is worse than a
// sentence explaining there is not one.
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.layout
import cortado.geometry
import cortado.events
import std.io

const TITLE_QUERY: int = 501

/// The page cortado shows when there is nothing to show.
///
/// A raw string, because markup is full of braces and an ordinary Beans string
/// would read `{` as the start of an interpolation. A raw string ends at the
/// first `"`, so there is not one anywhere in here — every attribute and every
/// string in the script below is single-quoted, which HTML and JavaScript both
/// allow and which keeps the page one literal rather than three concatenated
/// ones.
fn welcome() -> string {
    return r"<!doctype html>
<meta charset='utf-8'>
<title>cortado</title>
<style>
  body { font: 15px -apple-system, system-ui, sans-serif; margin: 2rem; color: #222 }
  button { font: inherit; padding: .4rem .8rem }
</style>
<h1>A page inside a native window</h1>
<p>This markup was handed straight to the engine. No server, no network.</p>
<button id='talk'>Talk to the program</button>
<script>
  document.getElementById('talk').addEventListener('click', function () {
    var post = window.webkit && window.webkit.messageHandlers.cortado;
    if (post) post.postMessage('the page says hello');
  });
</script>
"
}

fn run() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.gui)
    app.check_abi()?

    var window: surface.Window = app.window(640.0, 480.0, "Browser")?
    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?

    var address: widgets.TextField = widgets.TextField.of("")?
    address.set_hint("Type a URL and press return")?
    var back: widgets.Button = widgets.Button.of("Back")?
    var forward: widgets.Button = widgets.Button.of("Forward")?
    var heard: widgets.Label = widgets.Label.of("")?

    let here: bool = widgets.WebView.offered()
    var page: widgets.WebView = new widgets.WebView()
    var excuse: widgets.Label = widgets.Label.of("")?

    root.add(back)?
    root.add(forward)?
    root.add(address)?
    if here {
        page = widgets.WebView.of()?
        root.add(page)?
    } else {
        excuse.set_text("This platform has no browser engine. WKWebView is part of macOS and iOS; GTK's is a separate library and Windows' is a redistributable.")?
        root.add(excuse)?
    }
    root.add(heard)?

    // ------------------------------------------------------------ the layout

    var sheet: widgets.WidgetLayout = new widgets.WidgetLayout()
    var body: layout.FlexLayout = layout.FlexLayout.column(8.0)
    body.set_padding(geometry.EdgeInsets.all(12.0))
    body.set_align(geometry.Align.stretch)
    var frame: layout.LayoutNode = sheet.group("page", root, body)?

    var bar: layout.FlexLayout = layout.FlexLayout.row(8.0)
    var row: layout.LayoutNode = sheet.spacer("bar", bar)
    var go_back: layout.LayoutNode = sheet.leaf("back", back)
    go_back.spec = layout.LayoutSpec.fixed(72.0, 24.0)
    row.add(go_back)
    var go_on: layout.LayoutNode = sheet.leaf("forward", forward)
    go_on.spec = layout.LayoutSpec.fixed(84.0, 24.0)
    row.add(go_on)
    var where: layout.LayoutNode = sheet.leaf("address", address)
    where.spec = layout.LayoutSpec.flexible(1.0)
    row.add(where)
    frame.add(row)

    var canvas: layout.LayoutNode = if here { sheet.leaf("web", page) }
                                    else { sheet.leaf("excuse", excuse) }
    canvas.spec = layout.LayoutSpec.flexible(1.0)
    frame.add(canvas)
    frame.add(sheet.leaf("heard", heard))

    var solver: layout.Solver = new layout.Solver(sheet)
    let content: geometry.Size = window.content_size()?
    solver.solve(frame, geometry.Rect.at(geometry.Point.zero(), content))?
    sheet.apply(frame)?

    // ------------------------------------------------------------ the wiring

    if here {
        // The invitation. Without this line the button in the page posts into
        // nothing and the program never hears it.
        page.listen("cortado")?

        app.router.on(page.handle(), events.EventKind.web_finished,
            fn(event: events.UiEvent) {
                // Filled in here and not where `load` was called, because
                // `load` has not loaded anything yet when it returns.
                match page.url() {
                    ok(now) => { address.set_value(now) }
                    err(problem) => {}
                }
                page.eval("document.title", TITLE_QUERY)
            })

        app.router.on(page.handle(), events.EventKind.web_failed,
            fn(event: events.UiEvent) {
                heard.set_text("that page did not arrive (error {event.token})")
            })

        app.router.on(page.handle(), events.EventKind.web_message,
            fn(event: events.UiEvent) {
                match page.collect(event.token) {
                    ok(words) => { heard.set_text(words) }
                    err(problem) => { heard.set_text("{problem.kind}: {problem.msg}") }
                }
            })

        app.router.on(page.handle(), events.EventKind.web_result,
            fn(event: events.UiEvent) {
                if event.token != TITLE_QUERY { return }
                match page.collect(event.token) {
                    ok(name) => { window.set_title(name) }
                    err(problem) => {}
                }
            })

        app.router.on(address.handle(), events.EventKind.text_commit,
            fn(event: events.UiEvent) {
                match page.load(event.text) {
                    ok(going) => { heard.set_text("") }
                    err(problem) => { heard.set_text("{problem.msg}") }
                }
            })

        app.router.on(back.handle(), events.EventKind.activate,
            fn(event: events.UiEvent) {
                match page.go_back() {
                    ok(went) => {}
                    err(problem) => { heard.set_text("nothing to go back to") }
                }
            })

        app.router.on(forward.handle(), events.EventKind.activate,
            fn(event: events.UiEvent) {
                match page.go_forward() {
                    ok(went) => {}
                    err(problem) => { heard.set_text("nothing to go forward to") }
                }
            })

        page.load_html(welcome(), "")?
    }

    io.println("a browser engine here: {here}")

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
