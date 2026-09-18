package main

import cortado_skia
import cortado.geometry
import cortado.widgets
import cortado.paint
import cortado.component
import cortado.visual
import cortado.render
import {DrawingPage} from rendered_demo.generated.site
import std.io

fn require(value: bool, message: string) { if !value { panic(message) } }

fn drawing_nodes(root: widgets.Widget) -> List<widgets.Widget> {
    var result: List<widgets.Widget> = []
    if root.kind() == widgets.WidgetKind.canvas { result.push(root) }
    for child: widgets.Widget in root.children() {
        for found: widgets.Widget in drawing_nodes(child) { result.push(found) }
    }
    return move result
}

fn verify() -> Result<bool> {
    let scene: cortado_skia.Scene = new cortado_skia.Scene(geometry.Size.of(700.0, 370.0))
    let page: DrawingPage = new DrawingPage()
    scene.show(page)?
    require(!scene.has_active_animations(), "initial markup started a transition")
    let nodes: List<widgets.Widget> = drawing_nodes(scene.root())
    require(nodes.len() == 4, "markup did not create four drawing nodes")
    let shot: widgets.Snapshot = scene.renderer().snapshot()?
    require(shot.width == 700 && shot.height == 370, "drawing snapshot size changed")
    for node: widgets.Widget in nodes {
        let frame: geometry.Rect = scene.global_frame(node.render_object()?)?
        require(frame.width >= 60.0 && frame.height >= 80.0, "drawing node lost its frame")
        let center: widgets.Rgba = shot.pixel((frame.x + frame.width / 2.0) as int,
                                             (frame.y + frame.height / 2.0) as int)?
        require(center.red < 240 || center.green < 240 || center.blue < 240,
                "drawing node painted no visible shape")
    }
    let rectangle: geometry.Rect = scene.global_frame(nodes[0].render_object()?)?
    let top: widgets.Rgba = shot.pixel((rectangle.x + rectangle.width / 2.0) as int,
                                      (rectangle.y + 18.0) as int)?
    let bottom: widgets.Rgba = shot.pixel((rectangle.x + rectangle.width / 2.0) as int,
                                         (rectangle.y + rectangle.height - 18.0) as int)?
    require(bottom.red > top.red + 30,
            "transparent gradient endpoint did not fade into the background")
    let ellipse: geometry.Rect = scene.global_frame(nodes[1].render_object()?)?
    let shadow: widgets.Rgba = shot.pixel((ellipse.x + ellipse.width + 9.0) as int,
                                         (ellipse.y + ellipse.height / 2.0) as int)?
    require(shadow.red < 250 || shadow.green < 250 || shadow.blue < 250,
            "drop shadow did not paint outside the ellipse")
    let image: geometry.Rect = scene.global_frame(nodes[3].render_object()?)?
    let clipped: widgets.Rgba = shot.pixel((image.x + 1.0) as int, (image.y + 1.0) as int)?
    require(clipped.red > 245 && clipped.green > 245 && clipped.blue > 245,
            "image rounded clip did not clear the corner")
    let outer: geometry.Rect = scene.global_visual_frame(nodes[0].render_object()?)?
    require(outer.width > rectangle.width, "rotated visual bounds were not expanded")
    let retained: render.RenderObject = nodes[0].render_object()?
    let initial_color: int = retained.integer(visual.GRADIENT_START)?
    require(retained.real(visual.ROTATION)? == -8.0, "initial rotation was not immediate")
    page.toggle()
    scene.refresh()?
    require(scene.has_active_animations(), "changed .bx state did not schedule a frame")
    require(retained.real(visual.ROTATION)? == -8.0, "transition jumped before its first frame")
    let transform_semantics: int = scene.context().invalidation().semantics_version()
    scene.advance(0.1)?
    require(scene.context().invalidation().semantics_version() > transform_semantics,
            "animated visual bounds did not update semantics")
    let quarter: f64 = retained.real(visual.ROTATION)?
    require(quarter > -5.51 && quarter < -5.49, "ease_in_out quarter rotation is wrong")
    scene.advance(0.1)?
    let halfway: f64 = retained.real(visual.ROTATION)?
    require(halfway > -0.01 && halfway < 0.01, "ease_in_out halfway rotation is wrong")
    let mid_color: int = retained.integer(visual.GRADIENT_START)?
    require(mid_color != initial_color && mid_color != 0xed8054ff,
            "colour did not interpolate at half time")
    scene.advance(0.2)?
    require(!scene.has_active_animations(), "finished transition kept the frame clock active")
    require(retained.real(visual.ROTATION)? == 8.0, "transition did not reach its target")
    page.toggle()
    scene.refresh()?
    scene.advance(0.1)?
    let reversing_from: f64 = retained.real(visual.ROTATION)?
    require(reversing_from < 8.0 && reversing_from > -8.0, "reverse transition did not start")
    page.toggle()
    scene.refresh()?
    require(retained.real(visual.ROTATION)? == reversing_from,
            "interrupted transition jumped instead of starting from its current value")
    scene.advance(0.4)?
    require(retained.real(visual.ROTATION)? == 8.0 && !scene.has_active_animations(),
            "interrupted transition did not settle")
    retained.set_integer(visual.GRADIENT_START, 0x50a050ff)?
    require(scene.has_active_animations(), "color-only change did not start a transition")
    let color_semantics: int = scene.context().invalidation().semantics_version()
    let color_paint: int = scene.context().invalidation().paint_version()
    scene.advance(0.2)?
    require(scene.context().invalidation().paint_version() > color_paint,
            "color-only transition did not repaint")
    require(scene.context().invalidation().semantics_version() == color_semantics,
            "color-only transition rebuilt semantics")
    scene.advance(0.2)?
    require(scene.context().invalidation().semantics_version() == color_semantics,
            "color-only transition rebuilt semantics at completion")
    scene.close()
    match retained.set_real(visual.ROTATION, 10.0) {
        ok(_) => { panic("stale visual setter changed a closed scene") }
        err(problem) => { require(problem.kind == "stale", "stale visual setter had the wrong kind") }
    }
    let native_shape: component.Element = new component.Element(widgets.WidgetKind.canvas, "Rectangle")
    match component.WidgetMaker.make(native_shape) {
        ok(_) => { panic("shared drawing node leaked into the native factory") }
        err(problem) => { require(problem.kind == "unsupported", "native shape refusal had the wrong kind") }
    }
    let native_image: component.Element = new component.Element(widgets.WidgetKind.canvas, "ResourceImage")
    match component.WidgetMaker.make(native_image) {
        ok(_) => { panic("shared ResourceImage leaked into the native factory") }
        err(problem) => { require(problem.kind == "unsupported", "native image refusal had the wrong kind") }
    }
    let renderer: cortado_skia.SkiaRenderer = new cortado_skia.SkiaRenderer()
    match renderer.image("examples/rendered/assets/no-such-image.png") {
        ok(_) => { panic("missing image resource loaded") }
        err(problem) => { require(problem.kind == "image_load", "missing image used the wrong error kind") }
    }
    let canvas: paint.Canvas = renderer.begin(geometry.Size.of(20.0, 20.0), 1.0, 0xffffffff)?
    match canvas.path("M 0", 0x000000ff, 0, 0.0) {
        ok(_) => { panic("bad dynamic SVG path was accepted") }
        err(_) => {}
    }
    renderer.end()?
    renderer.close()
    io.println("ok .bx shapes, gradient, shadow, clipped image, transforms and stale setter")
    return ok(true)
}

fn main() { match verify() { ok(_) => {} err(problem) => { panic(problem.msg) } } }
