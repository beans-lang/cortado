package main

import cortado_skia
import cortado.geometry
import cortado.widgets
import {RendererPage} from rendered_demo.generated.site
import std.io

fn require(value: bool, message: string) { if !value { panic(message) } }

fn verify() -> Result<bool> {
    let scene: cortado_skia.Scene = new cortado_skia.Scene(geometry.Size.of(720.0, 260.0))
    let page: RendererPage = new RendererPage()
    page.attach(scene.renderer())
    scene.show(page)?
    require(page.active == "software", "page did not show initial backend")
    page.choose(cortado_skia.Backend.automatic)
    scene.refresh()?
    require(page.active == scene.renderer().backend().name(), "page did not show selected backend")
    page.choose(cortado_skia.Backend.software)
    scene.refresh()?
    require(page.active == "software", "page did not recover software")
    require(scene.refresh()? == false, "idle scene repainted without a change")
    let same: cortado_skia.Backend = scene.renderer().backend()
    scene.renderer().select_backend(same)?
    require(scene.refresh()?, "same-backend selection did not repaint")
    require(!scene.refresh()?, "same-backend selection repainted twice")
    let selected: widgets.Snapshot = scene.snapshot()?
    require(selected.width == 720 && selected.height == 260, "backend snapshot dimensions changed")
    // Asking the whole frame, not one pixel that used to sit on a tint.
    require(!selected.is_uniform()?, "backend snapshot was blank")
    scene.renderer().recover_software()?
    require(scene.refresh()?, "idle software recovery did not repaint")
    require(!scene.refresh()?, "software recovery repainted twice")
    scene.close()
    io.println("ok .bx renderer page selection and recovery")
    return ok(true)
}

fn main() { match verify() { ok(_) => {} err(problem) => { panic(problem.msg) } } }
