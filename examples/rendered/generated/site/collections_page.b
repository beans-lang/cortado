// Generated from site/collections_page.bx by cortado. Do not edit.
//
// The <beans> block below is collections_page.bx's, copied through byte for byte; its
// own package line is blanked so every line after it keeps its number. The
// render method under it is the markup, as Builder calls.
// Change collections_page.bx and regenerate:
//
//     cortado generate site/collections_page.bx
package site

import {Builder, Component} from cortado.component
import {UiEvent} from cortado.events


//          

import cortado.component
import cortado.widgets
import {view} from cortado.annotations

pub class DemoTableRows implements widgets.TableRows {
    pub calls: int = 0
    pub total: int = 10000
    pub fn init() {}
    pub fn row_count() -> int { return self.total }
    pub fn cell(row: int, column: int) -> string {
        self.calls += 1
        return if column == 0 { "Order {row}" } else { "Cup {row % 3}" }
    }
}

@view
pub partial class CollectionsPage extends component.Component {
    pub drinks: List<string> = ["Tea", "Coffee", "Water"]
    pub sizes: List<string> = ["Small", "Medium", "Large"]
    pub drink_index: int = 1
    pub last_drink_text: string = ""
    pub last_drink_value: f64 = -1.0
    pub size_index: int = 0
    pub tab_index: int = 0
    pub tab_labels: List<string> = ["Summary", "History"]
    pub divider: f64 = 190.0
    pub table_rows: DemoTableRows
    pub table_titles: List<string> = ["Order", "Cup"]
    pub table_widths: List<f64> = [210.0, 190.0]
    pub selected_row: int = -1
    pub fn init() { self.table_rows = new DemoTableRows(); super.init() }
    pub fn choose_drink(index: int, text: string, value: f64) {
        self.drink_index = index; self.last_drink_text = text; self.last_drink_value = value
        self.request_render()
    }
    pub fn choose_size(index: int) { self.size_index = index; self.request_render() }
    pub fn choose_tab(index: int) { self.tab_index = index; self.request_render() }
    pub fn move_divider(index: int) { self.divider = index as f64; self.request_render() }
    pub fn choose_row(index: int) { self.selected_row = index; self.request_render() }
    pub fn replace_drinks() {
        self.drinks = ["Water", "Tea"]
        self.drink_index = 1
        self.request_render()
    }
}

partial class CollectionsPage {
    pub override fn render(b: Builder) {
        b.open("VStack")  // collections_page.bx:1
        b.number("padding", (20) as f64)
        b.number("spacing", (12) as f64)
        b.word("align", "stretch")
        b.open("Label")  // collections_page.bx:2
        b.text("Choices and collections")
        b.number("font_size", (23) as f64)
        b.close()
        b.open("Label")  // collections_page.bx:3
        b.text("The item lists are typed Beans values in .bx.")
        b.word("text_color", "#555b6b")
        b.close()
        b.open("Label")  // collections_page.bx:4
        b.text("Drink")
        b.close()
        b.open("ComboBox")  // collections_page.bx:5
        b.key("{"drink"}")
        b.number("selected", (self.drink_index) as f64)
        b.items(self.drinks)
        b.on("change", fn(e: UiEvent) { self.choose_drink(e.index, e.text, e.position.x) })
        b.close()
        b.open("Label")  // collections_page.bx:7
        b.text("Cup size")
        b.close()
        b.open("Segmented")  // collections_page.bx:8
        b.key("{"size"}")
        b.number("selected", (self.size_index) as f64)
        b.items(self.sizes)
        b.on("change", fn(e: UiEvent) { self.choose_size(e.index) })
        b.close()
        b.open("Label")  // collections_page.bx:10
        b.text("Drink {self.drink_index}, size {self.size_index}")
        b.word("text_color", "#555b6b")
        b.close()
        b.open("Label")  // collections_page.bx:11
        b.text("Tabs")
        b.close()
        b.open("TabView")  // collections_page.bx:12
        b.key("{"tabs"}")
        b.number("selected", (self.tab_index) as f64)
        b.labels(self.tab_labels)
        b.number("height", (116) as f64)
        b.on("change", fn(e: UiEvent) { self.choose_tab(e.index) })
        b.open("VStack")  // collections_page.bx:14
        b.key("{"summary"}")
        b.number("padding", (10) as f64)
        b.word("align", "stretch")
        b.open("Label")  // collections_page.bx:15
        b.text("Summary page")
        b.close()
        b.close()
        b.open("VStack")  // collections_page.bx:17
        b.key("{"history"}")
        b.number("padding", (10) as f64)
        b.word("align", "stretch")
        b.open("Label")  // collections_page.bx:18
        b.text("History page")
        b.close()
        b.close()
        b.close()
        b.open("Label")  // collections_page.bx:21
        b.text("Split panes")
        b.close()
        b.open("SplitView")  // collections_page.bx:22
        b.key("{"split"}")
        b.flag("stacked", false)
        b.number("divider", (self.divider) as f64)
        b.number("height", (108) as f64)
        b.on("change", fn(e: UiEvent) { self.move_divider(e.index) })
        b.open("VStack")  // collections_page.bx:24
        b.key("{"left"}")
        b.number("padding", (10) as f64)
        b.word("background", "#e9edfa")
        b.word("align", "stretch")
        b.open("Label")  // collections_page.bx:25
        b.text("Left pane")
        b.close()
        b.close()
        b.open("VStack")  // collections_page.bx:27
        b.key("{"right"}")
        b.number("padding", (10) as f64)
        b.word("background", "#ebf3ec")
        b.word("align", "stretch")
        b.open("Label")  // collections_page.bx:28
        b.text("Right pane")
        b.close()
        b.close()
        b.close()
        b.open("Label")  // collections_page.bx:31
        b.text("Virtual table")
        b.close()
        b.open("Table")  // collections_page.bx:32
        b.key("{"orders"}")
        b.columns(self.table_titles)
        b.column_widths(self.table_widths)
        b.table_source(self.table_rows)
        b.number("height", (156) as f64)
        b.on("select", fn(e: UiEvent) { self.choose_row(e.index) })
        b.close()
        b.open("Label")  // collections_page.bx:35
        b.text("Selected row {self.selected_row}")
        b.word("text_color", "#555b6b")
        b.close()
        b.close()
    }
}
