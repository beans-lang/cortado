// Generated from templates/combo_box_popup_template.bx by cortado. Do not edit.
//
// The <beans> block below is combo_box_popup_template.bx's, copied through byte for byte; its
// own package line is blanked so every line after it keeps its number. The
// render method under it is the markup, as Builder calls.
// Change combo_box_popup_template.bx and regenerate:
//
//     cortado generate templates/combo_box_popup_template.bx
package templates

import {Builder, Component} from cortado.component
import {UiEvent} from cortado.events


//               
import cortado.component
import cortado.render
import {view} from cortado.annotations

@view
pub partial class ComboBoxPopupTemplate extends component.ChoiceControlTemplate {
    actions: Option<render.ControlActions> = none
    pub fn init() { super.init() }
    pub override fn bind_actions(actions: render.ControlActions) { self.actions = some(actions) }
    pub fn choose(index: int) {
        match self.actions {
            some(actions) => {
                actions.choose(index, index as f64).expect("choose a combo box option")
                actions.dismiss()
            }
            none => { panic("combo box popup has no actions") }
        }
    }
    pub override fn decorate_popup(root: render.RenderObject) -> Result<bool> {
        let found: int = self.decorate_rows(root, 0)?
        if found != self.choices.len() { return err("combo popup rows do not match choices", "tree_drift") }
        return ok(true)
    }
    fn decorate_rows(node: render.RenderObject, start: int) -> Result<int> {
        var index: int = start
        match node as? render.ButtonRender {
            some(button) => {
                if index >= self.choices.len() { return err("combo popup has an extra option", "tree_drift") }
                button.set_semantics("option", self.choices[index],
                    if index == self.selected { "selected" } else if index == self.highlighted { "highlighted" } else { "" })?
                index += 1
            }
            none => {}
        }
        for child_index: int in 0..node.child_count() {
            match node.child_at(child_index) {
                some(child) => { index = self.decorate_rows(child, index)? }
                none => {}
            }
        }
        return ok(index)
    }
}

partial class ComboBoxPopupTemplate {
    pub override fn render(b: Builder) {
        b.open("ScrollView")  // combo_box_popup_template.bx:1
        b.word("background", self.card)
        b.word("border_color", self.separator)
        b.number("border_width", (1) as f64)
        b.number("corner_radius", (self.radius_medium) as f64)
        b.open("VStack")  // combo_box_popup_template.bx:2
        b.number("spacing", (0) as f64)
        b.word("align", "stretch")
        var _cortado_row_0: int = 0
        for index in 0..self.choices.len() {  // combo_box_popup_template.bx:3
            b.open("Button")  // combo_box_popup_template.bx:4
            b.key("{"option-{index}"}")
            b.text("{if index == self.highlighted { "▸ {self.choices[index]}" } else if index == self.selected { "✓ {self.choices[index]}" } else { "  {self.choices[index]}" }}")
            b.number("height", (20) as f64)
            b.on("click", fn(e: UiEvent) { self.choose(index) })
            b.close()
            _cortado_row_0 += 1
        }
        b.close()
        b.close()
    }
}
