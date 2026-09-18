// Generated from templates/separator_template.bx by cortado. Do not edit.
//
// The <beans> block below is separator_template.bx's, copied through byte for byte; its
// own package line is blanked so every line after it keeps its number. The
// render method under it is the markup, as Builder calls.
// Change separator_template.bx and regenerate:
//
//     cortado generate templates/separator_template.bx
package templates

import {Builder, Component} from cortado.component
import {UiEvent} from cortado.events


//               
import cortado.component
import {view} from cortado.annotations
@view
pub partial class SeparatorTemplate extends component.ControlTemplate {
    pub fn init() { super.init() }
}

partial class SeparatorTemplate {
    pub override fn render(b: Builder) {
        b.open("Box")  // separator_template.bx:1
        b.word("background", "#bec2cd")
        b.close()
    }
}
