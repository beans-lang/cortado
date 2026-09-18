package main

import cortado_skia
import cortado.geometry
import {Screen, Gallery} from rendered_demo.generated.site
import {GalleryTemplates} from rendered_demo.theme
import std.io
import std.os
import cortado.surface
import cortado.platform
import cortado.widgets
import cortado.events

fn run() -> Result<bool> {
    let scene: cortado_skia.Scene = new cortado_skia.Scene(geometry.Size.of(520.0, 470.0))
    scene.show(new Screen())?
    scene.renderer().write_png("build/rendered.png")?
    scene.close()
    io.println("rendered .bx screen to build/rendered.png")
    return ok(true)
}

fn gallery(windowed: bool) -> Result<bool> {
    let view: Gallery = new Gallery()
    if windowed {
        let app: surface.Application = new surface.Application(platform.AppRole.gui)
        let window: cortado_skia.Window = cortado_skia.Window.open(app, geometry.Size.of(840.0, 760.0),
            "Cortado rendered gallery", view)?
        window.scene().use_templates(new GalleryTemplates())
        view.attach(window.scene().renderer())
        view.use_theme(window.scene().context().theme())
        window.refresh()?
        app.run()
        let problem: string = window.last_error()
        window.close(); app.shutdown()
        if problem != "" { return err(problem, "renderer_error") }
    } else {
        let scene: cortado_skia.Scene = new cortado_skia.Scene(geometry.Size.of(840.0, 760.0))
        scene.use_templates(new GalleryTemplates())
        view.attach(scene.renderer())
        view.use_theme(scene.context().theme())
        scene.show(view)?
        for page: int in 0..Gallery.page_count() {
            view.select(page)
            scene.refresh()?
            scene.renderer().write_png("build/rendered-gallery-{page}.png")?
        }
        scene.close()
        io.println("rendered gallery pages to build/rendered-gallery-*.png")
    }
    return ok(true)
}

fn button_at(root: widgets.Widget, offset: geometry.Point) -> Option<geometry.Point> {
    let frame: geometry.Rect = root.frame().expect("read control frame")
    let point: geometry.Point = geometry.Point.at(offset.x + frame.x, offset.y + frame.y)
    if root.kind() == widgets.WidgetKind.button {
        return some(geometry.Point.at(point.x + frame.width / 2.0, point.y + frame.height / 2.0))
    }
    for child: widgets.Widget in root.children() {
        match button_at(child, point) { some(found) => { return some(found) } none => {} }
    }
    return none
}

fn windowed(smoke: bool) -> Result<bool> {
    let app: surface.Application = new surface.Application(if smoke { platform.AppRole.headless } else { platform.AppRole.gui })
    let view: Screen = new Screen()
    let window: cortado_skia.Window = cortado_skia.Window.open(app, geometry.Size.of(520.0, 470.0),
        "Cortado shared renderer", view)?
    if smoke {
        let canvas: widgets.Widget = window.native_window().root_widget().expect("window surface")
        canvas.click_as_user(button_at(window.scene().root(), geometry.Point.zero()).expect("button point"))?
        app.run_for(0.1)?
        if view.orders != 1 { return err("native surface did not route click to Beans", "test") }
        if platform.Capability.snapshot.available() {
            let point: geometry.Point = button_at(window.scene().root(), geometry.Point.zero()).expect("button point")
            let size: geometry.Size = window.native_window().content_size()?
            let shown: widgets.Snapshot = canvas.snapshot()?
            let expected: widgets.Snapshot = window.scene().renderer().snapshot()?
            let a: widgets.Rgba = shown.pixel(((point.x - 100.0) * shown.width as f64 / size.width) as int,
                                              (point.y * shown.height as f64 / size.height) as int)?
            let b: widgets.Rgba = expected.pixel(((point.x - 100.0) * expected.width as f64 / size.width) as int,
                                                  (point.y * expected.height as f64 / size.height) as int)?
            if !a.same_as(b) { return err("native canvas did not display Skia pixels", "test") }
        }
        let second: cortado_skia.Window = cortado_skia.Window.open(app, geometry.Size.of(320.0, 320.0), "second", new Screen())?
        if second.scene().root().handle().raw == window.scene().root().handle().raw {
            return err("two windows shared render handles", "test")
        }
        second.close()
        window.native_window().resize_as_user(geometry.Size.of(560.0, 480.0))?
        app.run_for(0.1)?
    } else { app.run() }
    let problem: string = window.last_error()
    window.close()
    if app.router.watching() != 0 { return err("window left event watches behind", "test") }
    app.shutdown()
    if problem != "" { return err(problem, "renderer_error") }
    return ok(true)
}

fn main() {
    let args: List<string> = os.args()
    let mode: string = if args.len() > 0 { args[0] } else { "--snapshot" }
    let result: Result<bool> = if mode == "--window" || mode == "--gallery" {
        gallery(true)
    } else if mode == "--gallery-snapshot" { gallery(false)
    } else if mode == "--window-smoke" {
        windowed(true)
    } else { run() }
    match result { ok(_) => {} err(problem) => { panic(problem.msg) } }
}
