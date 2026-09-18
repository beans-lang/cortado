// Generated from site/popup_clip_probe.bx by cortado. Do not edit.
//
// The <beans> block below is popup_clip_probe.bx's, copied through byte for byte; its
// own package line is blanked so every line after it keeps its number. The
// render method under it is the markup, as Builder calls.
// Change popup_clip_probe.bx and regenerate:
//
//     cortado generate site/popup_clip_probe.bx
package site

import {Builder, Component} from cortado.component
import {UiEvent} from cortado.events


//          
import cortado.component
import {view} from cortado.annotations

@view
pub partial class PopupClipProbe extends component.Component {
    pub items: List<string> = ["Tea", "Coffee", "Water"]
    pub selected: int = 0
    pub fn init() { super.init() }
    pub fn choose(index: int) { self.selected = index; self.request_render() }
}

partial class PopupClipProbe {
    pub override fn render(b: Builder) {
        b.open("VStack")  // popup_clip_probe.bx:1
        b.number("padding", (12) as f64)
        b.number("spacing", (4) as f64)
        b.word("align", "stretch")
        b.open("ScrollView")  // popup_clip_probe.bx:2
        b.number("height", (56) as f64)
        b.open("VStack")  // popup_clip_probe.bx:3
        b.word("align", "stretch")
        b.open("ComboBox")  // popup_clip_probe.bx:4
        b.key("{"clipped-owner"}")
        b.items(self.items)
        b.number("selected", (self.selected) as f64)
        b.number("height", (30) as f64)
        b.on("change", fn(e: UiEvent) { self.choose(e.index) })
        b.close()
        b.close()
        b.close()
        b.close()
    }
}
