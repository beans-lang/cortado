package main

import cortado_skia
import cortado.geometry
import cortado.events
import cortado.widgets
import cortado.render
import {Gallery} from rendered_demo.generated.site
import {GalleryTemplates} from rendered_demo.theme
import std.io

fn require(value: bool, message: string) { if !value { panic(message) } }
fn find(root: widgets.Widget, title: string) -> Option<widgets.Widget> {
    if root.kind() == widgets.WidgetKind.button && root.display_text().expect("button title") == title { return some(root) }
    for child: widgets.Widget in root.children() {
        match find(child, title) { some(found) => { return some(found) } none => {} }
    }
    return none
}
fn verify_labels(root: widgets.Widget, scene: cortado_skia.Scene) -> Result<bool> {
    if root.kind() == widgets.WidgetKind.label {
        let text: string = root.display_text()?
        if text != "" {
            let frame: geometry.Rect = scene.global_frame(root.render_object()?)?
            require(frame.width > 0.0 && frame.height > 0.0, "label has no bounds: {text} ({frame.show()})")
            if text.starts_with("Type, select") || text.starts_with("Value:") {
                let pixels: widgets.Snapshot = scene.renderer().snapshot()?
                var ink: bool = false
                for y: int in frame.y as int..frame.bottom() as int {
                    for x: int in frame.x as int..frame.right() as int {
                        if x >= 0 && y >= 0 && x < pixels.width && y < pixels.height {
                            let pixel: widgets.Rgba = pixels.pixel(x, y)?
                            if pixel.red < 180 && pixel.green < 180 && pixel.blue < 180 { ink = true; break }
                        }
                    }
                    if ink { break }
                }
                let object: render.RenderObject = root.render_object()?
                require(ink, "label painted no text: {text} ({frame.show()}), hidden={object.is_hidden()}, ink={object.text_color()}, font={object.font_size()}")
            }
        }
    }
    for child: widgets.Widget in root.children() { verify_labels(child, scene)? }
    return ok(true)
}
fn verify() -> Result<bool> {
    let gallery: Gallery = new Gallery()
    let scene: cortado_skia.Scene = new cortado_skia.Scene(geometry.Size.of(840.0, 760.0))
    scene.use_templates(new GalleryTemplates())
    gallery.attach(scene.renderer())
    gallery.use_theme(scene.context().theme())
    scene.show(gallery)?
    let navigation: widgets.Widget = find(scene.root(), "Controls").expect("controls navigation")
    let handle: u64 = navigation.handle().raw
    let original: widgets.Widget = find(scene.root(), "Order coffee").expect("first page button")
    scene.semantics_action(handle, 1)?
    require(gallery.page == 1, "accessibility activation did not navigate")
    require(!original.is_alive(), "departed page left controls alive")
    scene.semantics_action(handle, 2)?
    require(navigation.render_object()?.focused(), "accessibility focus did not reach retained navigation")
    for page: int in 0..Gallery.page_count() {
        gallery.select(page)
        scene.refresh()?
        verify_labels(scene.root(), scene)?
        require(find(scene.root(), "Controls").expect("retained navigation").handle().raw == handle,
                "page switch replaced navigation controls")
        require(!scene.refresh()?, "gallery keeps drawing when idle")
        require(scene.semantics().len() > 5, "page has no semantics")
    }
    let count: int = scene.context().registry().count()
    for page: int in 0..Gallery.page_count() { gallery.select(page); scene.refresh()? }
    require(scene.context().registry().count() == count,
            "page changes leaked registered objects: {count} -> {scene.context().registry().count()}")
    gallery.select(5)
    scene.refresh()?
    let rating: widgets.Widget = find(scene.root(), "☆ 3").expect("custom rating button")
    scene.context().focus(rating.handle().raw)?
    scene.key(events.EventKind.key_down, events.Key.space)?
    require(find(scene.root(), "★ 3").expect("updated rating").handle().raw == rating.handle().raw,
            "custom .bx control lost state or keyed identity")
    find(scene.root(), "Coffee brown").expect("theme button").activate()?
    require(scene.refresh()?, "theme change did not repaint")
    require(scene.context().theme().accent() == 0x87582fff, "markup theme action did not set accent")
    let other: cortado_skia.Scene = new cortado_skia.Scene(geometry.Size.of(100.0, 100.0), 2)
    require(other.context().theme().accent() == 0x007affff, "theme change escaped its window")
    other.close()
    match scene.semantics_action(original.handle().raw, 1) {
        ok(_) => { panic("stale accessibility action was accepted") } err(_) => {}
    }
    scene.close()
    require(scene.context().registry().count() == 0 && scene.context().router().watching() == 0,
            "gallery teardown leaked objects or callbacks")
    io.println("ok gallery navigation, accessibility actions, identity, idle, teardown")
    return ok(true)
}
fn main() { match verify() { ok(_) => {} err(problem) => { panic(problem.msg) } } }
