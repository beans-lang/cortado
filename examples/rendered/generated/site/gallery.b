// Generated from site/gallery.bx by cortado. Do not edit.
//
// The <beans> block below is gallery.bx's, copied through byte for byte; its
// own package line is blanked so every line after it keeps its number. The
// render method under it is the markup, as Builder calls.
// Change gallery.bx and regenerate:
//
//     cortado generate site/gallery.bx
package site

import {Builder, Component} from cortado.component
import {UiEvent} from cortado.events


//          

import cortado.component
import cortado_skia
import cortado.render
import {view} from cortado.annotations

@view
pub partial class Gallery extends component.Component {
    pub page: int = 0
    pub renderer: Option<cortado_skia.SkiaRenderer> = none
    pub theme: Option<render.Theme> = none
    pub fn init() { super.init() }
    pub static fn page_count() -> int { return 9 }
    pub fn select(page: int) {
        if page < 0 || page >= Gallery.page_count() || page == self.page { return }
        self.page = page
        self.request_render()
    }
    pub fn attach(renderer: cortado_skia.SkiaRenderer) {
        self.renderer = some(renderer)
        self.request_render()
    }
    pub fn use_theme(theme: render.Theme) { self.theme = some(theme); self.request_render() }
}

// Every component tag in gallery.bx, checked by beansc rather than by cortado-bx:
// a tag whose type is not a Component is a type error naming the type,
// instead of a blank subtree and a fault at run time. Unused, and an
// unused free function is not an error.
fn _cortado_component_gallery_Screen(value: Screen) -> Component { return value }
fn _cortado_component_gallery_ControlsPage(value: ControlsPage) -> Component { return value }
fn _cortado_component_gallery_RendererPage(value: RendererPage) -> Component { return value }
fn _cortado_component_gallery_EditingPage(value: EditingPage) -> Component { return value }
fn _cortado_component_gallery_CollectionsPage(value: CollectionsPage) -> Component { return value }
fn _cortado_component_gallery_CompositionPage(value: CompositionPage) -> Component { return value }
fn _cortado_component_gallery_DrawingPage(value: DrawingPage) -> Component { return value }
fn _cortado_component_gallery_AccessibilityPage(value: AccessibilityPage) -> Component { return value }
fn _cortado_component_gallery_TablePage(value: TablePage) -> Component { return value }

partial class Gallery {
    pub override fn render(b: Builder) {
        b.open("VStack")  // gallery.bx:1
        b.number("spacing", (0) as f64)
        b.word("align", "stretch")
        b.open("VStack")  // gallery.bx:2
        b.number("padding", (20) as f64)
        b.number("spacing", (10) as f64)
        b.word("align", "stretch")
        b.word("background", "#ffffffff")
        b.open("Label")  // gallery.bx:3
        b.text("Cortado rendered gallery")
        b.number("font_size", (26) as f64)
        b.close()
        b.open("Label")  // gallery.bx:4
        b.text("Beans behavior. Markup visuals. One shared renderer.")
        b.word("text_color", "#555b6b")
        b.close()
        b.open("HStack")  // gallery.bx:5
        b.number("spacing", (8) as f64)
        b.flag("wrap", true)
        b.open("Button")  // gallery.bx:6
        b.text("Getting started")
        b.on("click", fn(e: UiEvent) { self.select(0) })
        b.close()
        b.open("Button")  // gallery.bx:7
        b.text("Controls")
        b.on("click", fn(e: UiEvent) { self.select(1) })
        b.close()
        b.open("Button")  // gallery.bx:8
        b.text("Graphics")
        b.on("click", fn(e: UiEvent) { self.select(2) })
        b.close()
        b.open("Button")  // gallery.bx:9
        b.text("Editing")
        b.on("click", fn(e: UiEvent) { self.select(3) })
        b.close()
        b.open("Button")  // gallery.bx:10
        b.text("Collections")
        b.on("click", fn(e: UiEvent) { self.select(4) })
        b.close()
        b.open("Button")  // gallery.bx:11
        b.text("Composition")
        b.on("click", fn(e: UiEvent) { self.select(5) })
        b.close()
        b.open("Button")  // gallery.bx:12
        b.text("Drawing")
        b.on("click", fn(e: UiEvent) { self.select(6) })
        b.close()
        b.open("Button")  // gallery.bx:13
        b.text("Accessibility")
        b.on("click", fn(e: UiEvent) { self.select(7) })
        b.close()
        b.open("Button")  // gallery.bx:14
        b.text("Tables")
        b.on("click", fn(e: UiEvent) { self.select(8) })
        b.close()
        b.close()
        b.close()
        b.open("ScrollView")  // gallery.bx:17
        b.number("grow", (1) as f64)
        if self.page == 0 {  // gallery.bx:18
            b.child<Screen>("c0", fn(_cortado_c: Screen) {  // gallery.bx:19
            })
        } else if self.page == 1 {  // gallery.bx:20
            b.child<ControlsPage>("c1", fn(_cortado_c: ControlsPage) {  // gallery.bx:21
            })
        } else if self.page == 2 {  // gallery.bx:22
            b.child<RendererPage>("c2", fn(_cortado_c: RendererPage) {  // gallery.bx:23
                _cortado_c.renderer = self.renderer
            })
        } else if self.page == 3 {  // gallery.bx:24
            b.child<EditingPage>("c3", fn(_cortado_c: EditingPage) {  // gallery.bx:25
            })
        } else if self.page == 4 {  // gallery.bx:26
            b.child<CollectionsPage>("c4", fn(_cortado_c: CollectionsPage) {  // gallery.bx:27
            })
        } else if self.page == 5 {  // gallery.bx:28
            b.child<CompositionPage>("c5", fn(_cortado_c: CompositionPage) {  // gallery.bx:29
                _cortado_c.theme = self.theme
            })
        } else if self.page == 6 {  // gallery.bx:30
            b.child<DrawingPage>("c6", fn(_cortado_c: DrawingPage) {  // gallery.bx:31
            })
        } else if self.page == 7 {  // gallery.bx:32
            b.child<AccessibilityPage>("c7", fn(_cortado_c: AccessibilityPage) {  // gallery.bx:33
            })
        } else {  // gallery.bx:34
            b.child<TablePage>("c8", fn(_cortado_c: TablePage) {  // gallery.bx:35
            })
        }
        b.close()
        b.close()
    }
}
