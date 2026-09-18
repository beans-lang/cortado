// Generated from site/table_page.bx by cortado. Do not edit.
//
// The <beans> block below is table_page.bx's, copied through byte for byte; its
// own package line is blanked so every line after it keeps its number. The
// render method under it is the markup, as Builder calls.
// Change table_page.bx and regenerate:
//
//     cortado generate site/table_page.bx
package site

import {Builder, Component} from cortado.component
import {UiEvent} from cortado.events


//          

import cortado.component
import cortado.widgets
import {view} from cortado.annotations

pub class EditableTableRows implements widgets.TableRows {
    pub calls: int = 0
    pub total: int = 10000
    values: Map<int, string> = {}
    pub fn init() {}
    pub fn row_count() -> int { return self.total }
    pub fn cell(row: int, column: int) -> string {
        self.calls += 1
        if column == 0 { return "Order {row}" }
        return match self.values.get(row) {
            some(value) => value
            none => "Cup {row % 3}"
        }
    }
    pub fn save(row: int, column: int, text: string) {
        if column == 1 { self.values[row] = text }
    }
}

@view
pub partial class TablePage extends component.Component {
    pub rows: EditableTableRows
    pub titles: List<string> = ["Order", "Cup"]
    pub widths: List<f64> = [210.0, 190.0]
    pub selected_row: int = -1
    pub last_edit: string = "none"
    pub save_edits: bool = true
    pub edit_policy: component.TableEditRule
    pub fn init() {
        self.rows = new EditableTableRows()
        self.edit_policy = new component.TableEditRule(fn(row: int, column: int) -> bool { return column == 1 })
        super.init()
    }
    pub fn choose_row(index: int) { self.selected_row = index; self.request_render() }
    pub fn commit_cell(row: int, column: int, text: string) {
        if self.save_edits { self.rows.save(row, column, text) }
        self.last_edit = "row {row}, column {column}: {text}"
        self.request_render()
    }
}

partial class TablePage {
    pub override fn render(b: Builder) {
        b.open("VStack")  // table_page.bx:1
        b.number("padding", (20) as f64)
        b.number("spacing", (12) as f64)
        b.word("align", "stretch")
        b.open("Label")  // table_page.bx:2
        b.text("Virtual table")
        b.number("font_size", (23) as f64)
        b.close()
        b.open("Label")  // table_page.bx:3
        b.text("10,000 rows. Scroll to see cells load only when visible.")
        b.word("text_color", "#555b6b")
        b.close()
        b.open("Label")  // table_page.bx:4
        b.text("Double-click a Cup cell, or select a row, choose a column with Left/Right, and press Return. Escape cancels.")
        b.word("text_color", "#555b6b")
        b.close()
        b.open("Table")  // table_page.bx:5
        b.key("{"orders"}")
        b.columns(self.titles)
        b.column_widths(self.widths)
        b.table_source(self.rows)
        b.editable_when(self.edit_policy)
        b.number("height", (340) as f64)
        b.on("select", fn(e: UiEvent) { self.choose_row(e.index) })
        b.on("commit", fn(e: UiEvent) { self.commit_cell(e.index, e.token, e.text) })
        b.close()
        b.open("Label")  // table_page.bx:9
        b.text("Selected row {self.selected_row}. Last edit: {self.last_edit}")
        b.word("text_color", "#555b6b")
        b.close()
        b.close()
    }
}
