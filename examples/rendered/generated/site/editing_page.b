// Generated from site/editing_page.bx by cortado. Do not edit.
//
// The <beans> block below is editing_page.bx's, copied through byte for byte; its
// own package line is blanked so every line after it keeps its number. The
// render method under it is the markup, as Builder calls.
// Change editing_page.bx and regenerate:
//
//     cortado generate site/editing_page.bx
package site

import {Builder, Component} from cortado.component
import {UiEvent} from cortado.events


//          

import cortado.component
import {view} from cortado.annotations

@view
pub partial class EditingPage extends component.Component {
    pub name: string = ""
    pub password: string = ""
    pub search: string = ""
    pub notes: string = ""
    pub fn init() { super.init() }
    pub fn clear() {
        self.name = ""
        self.password = ""
        self.search = ""
        self.notes = ""
        self.request_render()
    }
}

partial class EditingPage {
    pub override fn render(b: Builder) {
        b.open("VStack")  // editing_page.bx:1
        b.number("padding", (24) as f64)
        b.number("spacing", (12) as f64)
        b.word("align", "stretch")
        b.open("Label")  // editing_page.bx:2
        b.text("Editing and input methods")
        b.number("font_size", (24) as f64)
        b.close()
        b.open("Label")  // editing_page.bx:3
        b.text("Type, select, paste, and try your keyboard's input method.")
        b.close()
        b.open("Label")  // editing_page.bx:4
        b.text("Name")
        b.close()
        b.open("TextField")  // editing_page.bx:5
        b.key("{"name"}")
        b.on("commit", fn(_e: UiEvent) { self.name = _e.text })
        b.text("{self.name}")
        b.close()
        b.open("Label")  // editing_page.bx:6
        b.text("Value: {self.name}")
        b.close()
        b.open("Label")  // editing_page.bx:7
        b.text("Password")
        b.close()
        b.open("SecureField")  // editing_page.bx:8
        b.key("{"password"}")
        b.on("commit", fn(_e: UiEvent) { self.password = _e.text })
        b.text("{self.password}")
        b.close()
        b.open("Label")  // editing_page.bx:9
        b.text("Search")
        b.close()
        b.open("SearchField")  // editing_page.bx:10
        b.key("{"search"}")
        b.on("commit", fn(_e: UiEvent) { self.search = _e.text })
        b.text("{self.search}")
        b.close()
        b.open("Label")  // editing_page.bx:11
        b.text("Notes")
        b.close()
        b.open("TextArea")  // editing_page.bx:12
        b.key("{"notes"}")
        b.number("height", (110) as f64)
        b.on("commit", fn(_e: UiEvent) { self.notes = _e.text })
        b.text("{self.notes}")
        b.close()
        b.open("Label")  // editing_page.bx:13
        b.text("Use a screen reader to move through every field and button.")
        b.close()
        b.open("Button")  // editing_page.bx:14
        b.key("{"clear"}")
        b.text("Clear fields")
        b.on("click", fn(e: UiEvent) { self.clear() })
        b.close()
        b.close()
    }
}
