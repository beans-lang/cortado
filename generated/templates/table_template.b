// Generated from templates/table_template.bx by cortado. Do not edit.
//
// The <beans> block below is table_template.bx's, copied through byte for byte; its
// own package line is blanked so every line after it keeps its number. The
// render method under it is the markup, as Builder calls.
// Change table_template.bx and regenerate:
//
//     cortado generate templates/table_template.bx
package templates

import {Builder, Component} from cortado.component
import {UiEvent} from cortado.events


//               
import cortado.component
import cortado.render
import {view} from cortado.annotations

@view
pub partial class TableTemplate extends component.TableControlTemplate {
    actions: Option<render.ControlActions> = none
    pub fn init() { super.init() }
    pub override fn bind_actions(actions: render.ControlActions) { self.actions = some(actions) }
    pub fn commit(row: int, column: int, text: string) {
        match self.actions {
            some(actions) => { actions.commit_cell(row, column, text).expect("commit a table cell") }
            none => { panic("table template has no actions") }
        }
    }
}

partial class TableTemplate {
    pub override fn render(b: Builder) {
        b.open("Box")  // table_template.bx:1
        b.number("width", (self.total_width) as f64)
        b.word("background", self.fill)
        b.word("border_color", "#bfc3ce")
        b.number("border_width", (1) as f64)
        if self.total_rows == 0 {  // table_template.bx:2
            b.open("Label")  // table_template.bx:3
            b.number("x", (12) as f64)
            b.number("y", (self.header_height + 12.0) as f64)
            b.text("No rows")
            b.word("text_color", "#676d79")
            b.close()
        }
        var _cortado_row_0: int = 0
        for row in self.rows {  // table_template.bx:5
            b.open("HStack")  // table_template.bx:6
            b.key("{"row-{row.index}"}")
            b.number("y", (row.top) as f64)
            b.number("height", (self.row_height) as f64)
            b.number("width", (self.total_width) as f64)
            b.number("spacing", (0) as f64)
            b.word("align", "center")
            b.word("background", if row.selected { "#dce7ff" } else if row.index % 2 == 0 { "#ffffff" } else { "#f4f6fa" })
            var _cortado_row_1: int = 0
            for column in 0..row.cells.len() {  // table_template.bx:9
                if row.editable[column] {  // table_template.bx:10
                    b.open("TextField")  // table_template.bx:11
                    b.key("{"editor-{row.index}-{column}-{self.revision}"}")
                    b.text("{row.cells[column]}")
                    b.number("width", (self.widths[column]) as f64)
                    b.number("height", (self.row_height) as f64)
                    b.on("commit", fn(e: UiEvent) { self.commit(row.index, column, e.text) })
                    b.close()
                } else {  // table_template.bx:14
                    b.open("Label")  // table_template.bx:15
                    b.key("{"cell-{row.index}-{column}"}")
                    b.text("{row.cells[column]}")
                    b.number("width", (self.widths[column]) as f64)
                    b.number("font_size", (self.font_size) as f64)
                    b.word("text_color", self.ink)
                    b.close()
                }
                _cortado_row_1 += 1
            }
            b.close()
            _cortado_row_0 += 1
        }
        b.open("HStack")  // table_template.bx:21
        b.number("y", (0) as f64)
        b.number("height", (self.header_height) as f64)
        b.number("width", (self.total_width) as f64)
        b.number("spacing", (0) as f64)
        b.word("align", "center")
        b.word("background", "#dce0ea")
        var _cortado_row_2: int = 0
        for column in 0..self.titles.len() {  // table_template.bx:23
            b.open("Label")  // table_template.bx:24
            b.key("{"header-{column}"}")
            b.text("{self.titles[column]}")
            b.number("width", (self.widths[column]) as f64)
            b.number("font_size", (self.font_size) as f64)
            b.word("text_color", self.ink)
            b.close()
            _cortado_row_2 += 1
        }
        b.close()
        b.close()
    }
}
