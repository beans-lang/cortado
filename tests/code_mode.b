// The native text area keeps its text and chosen point size in code mode.
// This case runs on macOS, where AppKit supplies the editor.
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.host
import std.io

fn run() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.headless)
    app.check_abi()?

    var area: widgets.TextArea = widgets.TextArea.of("select 'a--b';")?
    io.println("starts in ordinary mode: {!area.is_code_mode()?}")
    area.set_font_size(14.0)?
    area.set_code_mode(true)?
    io.println("code mode turns on: {area.is_code_mode()?}")
    io.println("code mode keeps the text: {area.value()? == "select 'a--b';"}")
    io.println("code mode keeps the point size: {area.font_size()? == 14.0}")

    area.set_font_size(16.0)?
    io.println("font size can change in code mode: {area.font_size()? == 16.0}")
    area.set_code_mode(false)?
    io.println("ordinary mode returns: {!area.is_code_mode()?}")
    io.println("ordinary mode keeps the new point size: {area.font_size()? == 16.0}")
    io.println("turning code mode off keeps the text: {area.value()? == "select 'a--b';"}")

    match area.set_property(host.P_CODE_MODE, 2) {
        ok(done) => { io.println("invalid mode accepted") }
        err(problem) => { io.println("invalid mode refused: {problem.kind}") }
    }
    var label: widgets.Label = widgets.Label.of("SQL")?
    match label.set_property(host.P_CODE_MODE, 1) {
        ok(done) => { io.println("wrong control accepted") }
        err(problem) => { io.println("wrong control refused: {problem.kind}") }
    }

    app.shutdown()
    return ok(true)
}

fn main() {
    match run() {
        ok(done) => {}
        err(problem) => { io.println("{problem.kind}: {problem.msg}") }
    }
}
