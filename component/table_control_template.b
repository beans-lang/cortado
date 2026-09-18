package component

import cortado.render

/// One materialized row in a much larger source.
pub class TableVisibleRow {
    pub index: int
    pub top: f64
    pub cells: List<string>
    pub editable: List<bool>
    pub selected: bool
    pub fn init(index: int, top: f64, cells: List<string>, editable: List<bool>, selected: bool) {
        self.index = index; self.top = top; self.selected = selected
        self.cells = []
        for cell: string in cells { self.cells.push(cell) }
        self.editable = []
        for allowed: bool in editable { self.editable.push(allowed) }
    }
}

pub abstract class TableControlTemplate extends ControlTemplate {
    pub titles: List<string> = []
    pub widths: List<f64> = []
    pub rows: List<TableVisibleRow> = []
    pub total_rows: int = 0
    pub total_width: f64 = 0.0
    pub row_height: f64 = 28.0
    pub header_height: f64 = 30.0
    pub revision: int = -1
    offset_y: f64 = -1.0
    viewport_height: f64 = -1.0
    viewport_width: f64 = -1.0
    pub fn init() { super.init() }
    pub override fn update(control: render.RenderObject, theme: render.Theme) {
        super.update(control, theme)
        match control as? render.TableRender {
            some(table) => {
                let scroll_y: f64 = table.scroll_offset()
                let height: f64 = table.frame().height
                let width: f64 = table.frame().width
                if self.revision == table.version() && self.offset_y == scroll_y &&
                   self.viewport_width == width && self.viewport_height == height { return }
                self.revision = table.version()
                self.offset_y = scroll_y
                self.viewport_height = height
                self.viewport_width = width
                self.total_rows = table.row_count()
                self.row_height = table.row_height()
                self.header_height = table.header_height()
                self.titles = table.titles_copy()
                self.widths = table.widths_copy()
                self.total_width = width
                var columns_width: f64 = 0.0
                for column_width: f64 in self.widths { columns_width += column_width }
                if columns_width > self.total_width { self.total_width = columns_width }
                var visible: List<TableVisibleRow> = []
                // Keep the partly visible row; the opaque header covers its
                // portion above the table body.
                var first: int = (scroll_y / self.row_height) as int
                if first < 0 { first = 0 }
                var last: int = first + ((height - self.header_height) / self.row_height) as int + 2
                if last > self.total_rows { last = self.total_rows }
                if last < first { last = first }
                for row: int in first..last {
                    var cells: List<string> = []
                    var editable: List<bool> = []
                    for column: int in 0..self.titles.len() {
                        cells.push(table.cell(row, column).expect("visible table cell"))
                        editable.push(table.editable(row, column).expect("visible table policy"))
                    }
                    visible.push(new TableVisibleRow(row, self.header_height + row as f64 * self.row_height - scroll_y,
                                                     move cells, move editable, table.selected() == row))
                }
                self.rows = move visible
                self.request_render()
            }
            none => {}
        }
    }
}
