// Generated from site/renderer_page.bx by cortado. Do not edit.
//
// The <beans> block below is renderer_page.bx's, copied through byte for byte; its
// own package line is blanked so every line after it keeps its number. The
// render method under it is the markup, as Builder calls.
// Change renderer_page.bx and regenerate:
//
//     cortado generate site/renderer_page.bx
package site

import {Builder, Component} from cortado.component
import {UiEvent} from cortado.events


//          

import cortado.component
import cortado_skia
import {view, param} from cortado.annotations

@view
pub partial class RendererPage extends component.Component {
    @param pub renderer: Option<cortado_skia.SkiaRenderer> = none
    pub active: string = "software"
    pub status: string = "Choose a backend to draw the next frame."
    pub fn init() { super.init() }
    pub fn attach(renderer: cortado_skia.SkiaRenderer) {
        self.renderer = some(renderer)
        self.active = renderer.backend().name()
        self.request_render()
    }
    pub override fn on_params_set() {
        match self.renderer {
            some(renderer) => { self.active = renderer.backend().name() }
            none => { self.active = "software" }
        }
    }
    pub fn choose(preferred: cortado_skia.Backend) {
        match self.renderer {
            none => { self.status = "No renderer is attached." }
            some(renderer) => {
                match renderer.select_backend(preferred) {
                    ok(_) => {
                        self.active = renderer.backend().name()
                        self.status = "Drawing with {self.active}."
                    }
                    err(_) => { self.status = "This backend is unavailable here." }
                }
            }
        }
        self.request_render()
    }
}

partial class RendererPage {
    pub override fn render(b: Builder) {
        b.open("VStack")  // renderer_page.bx:1
        b.number("padding", (20) as f64)
        b.number("spacing", (12) as f64)
        b.word("align", "stretch")
        b.word("background", "#f7f7f9")
        b.open("Label")  // renderer_page.bx:2
        b.text("Graphics backend")
        b.number("font_size", (24) as f64)
        b.close()
        b.open("Label")  // renderer_page.bx:3
        b.text("Drawn by Skia; Canvas shows the GPU frame after readback.")
        b.word("text_color", "#555b6b")
        b.close()
        b.open("Label")  // renderer_page.bx:4
        b.text("Active: {self.active}")
        b.close()
        b.open("Label")  // renderer_page.bx:5
        b.text("{self.status}")
        b.word("text_color", "#555b6b")
        b.close()
        b.open("HStack")  // renderer_page.bx:6
        b.number("spacing", (8) as f64)
        b.open("Button")  // renderer_page.bx:7
        b.text("Automatic")
        b.on("click", fn(e: UiEvent) { self.choose(cortado_skia.Backend.automatic) })
        b.close()
        b.open("Button")  // renderer_page.bx:8
        b.text("Metal")
        b.on("click", fn(e: UiEvent) { self.choose(cortado_skia.Backend.metal) })
        b.close()
        b.open("Button")  // renderer_page.bx:9
        b.text("Vulkan")
        b.on("click", fn(e: UiEvent) { self.choose(cortado_skia.Backend.vulkan) })
        b.close()
        b.open("Button")  // renderer_page.bx:10
        b.text("OpenGL")
        b.on("click", fn(e: UiEvent) { self.choose(cortado_skia.Backend.opengl) })
        b.close()
        b.open("Button")  // renderer_page.bx:11
        b.text("Software")
        b.on("click", fn(e: UiEvent) { self.choose(cortado_skia.Backend.software) })
        b.close()
        b.close()
        b.close()
    }
}
