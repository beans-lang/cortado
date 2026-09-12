// cask — a database browser, shaped like the one everybody already knows.
//
//     beansc build examples/cask/main.b -o build/cask && ./build/cask
//     ./build/cask some.db          # or point it at a file
//
// **The layout is DBeaver's**, because that shape is what a person who
// browses databases already has in their hands: a navigator tree down the
// left, an editor with tabs on the right, the SQL editor split so the
// statement is above its results, and a status bar that says what you are
// connected to. Nothing here is a new idea, and that is the point.
//
// **Nothing above `cask.engine` knows what SQLite is.** A database is a
// `Connection`; a kind of database is a `Driver`; the window asks a registry
// to open whatever it was given. Adding PostgreSQL means writing two classes
// and one line in `main`, and the navigator, the editor, the report and this
// file do not change. That is the whole reason for the shape.
//
// This is also the example that exists to be *used* rather than read. Written
// against cortado, it found four bugs in it — a toolbar whose items all
// carried the first command's words, tab pages drawn on top of the tab strip,
// a split view that reported its own layout back as a value the user changed,
// and a layout spec whose obvious spelling silently meant "zero wide" — and
// one gap it could not fix: **there is no outline view**, so the navigator is
// a tree flattened into a table by hand. See `ui/navigator.b` and README.md.
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.layout
import cortado.geometry
import cortado.events
import cortado.host
import std.io
import std.os
import std.calendar
import {Connection, DbObject, Grid, ObjectKind, Registry} from cask.engine
import {SqliteDriver} from cask.sqlite_driver
import {Navigator, Report} from cask.ui

const REFRESH: int = 21
const EXECUTE: int = 22
const RENDER: int = 23
const ABOUT: int = 24

const SIDEBAR: f64 = 250.0
const PAGE: int = 500

/// Which tab is which. DBeaver opens an editor per object with these same
/// pages under it; cask has one editor, and the pages are the same.
const TAB_DATA: int = 0
const TAB_COLUMNS: int = 1
const TAB_DDL: int = 2
const TAB_SQL: int = 3
const TAB_REPORT: int = 4

/// What the window is looking at.
///
/// A class rather than a pile of captured `var`s: every handler needs to read
/// and write the same selection, and a closure captures a binding, not a
/// place.
class Session {
    pub link: Connection
    pub tree: Navigator
    pub chosen: string = ""
    pub kind: ObjectKind = ObjectKind.connection
    pub data: Grid = Grid.empty()
    pub answer: Grid = Grid.empty()
    pub divider: f64 = SIDEBAR
    pub editor: f64 = 150.0
    pub accent: widgets.Rgba = widgets.Rgba {red: 47, green: 111, blue: 79, alpha: 255}

    pub fn init(link: Connection, tree: Navigator) {
        self.link = link
        self.tree = tree
    }
}

fn run(target: string, showing: bool) -> Result<bool> {
    // ------------------------------------------------------ the drivers

    var drivers: Registry = new Registry()
    drivers.add(new SqliteDriver())
    let link: Connection = drivers.open(target)?
    let tree: Navigator = new Navigator(link)
    let state: Session = new Session(link, tree)

    // ------------------------------------------------------- the window

    var app: surface.Application = new surface.Application(
        if showing { platform.AppRole.gui } else { platform.AppRole.headless })
    app.check_abi()?

    var window: surface.Window = app.window(1000.0, 660.0, "cask")?
    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?

    // One command table, which becomes the toolbar where there is one and the
    // menu bar where there is one. Two lists would drift.
    var commands: surface.Menu = surface.Menu.of("cask")?
    commands.add("Refresh", "mod+r", surface.CommandRole.none, REFRESH)?
    commands.add("Execute", "mod+return", surface.CommandRole.none, EXECUTE)?
    commands.add("Report", "mod+p", surface.CommandRole.none, RENDER)?
    commands.separator()?
    commands.add("Connection", "mod+i", surface.CommandRole.none, ABOUT)?
    // The system's own icons, where the system has one. A role a platform
    // cannot draw is left as words rather than as an empty square — Windows
    // has no standard picture for "run", and a toolbar of blanks is worse
    // than a toolbar of labels.
    wear(commands, REFRESH, widgets.SystemIcon.refresh)
    wear(commands, EXECUTE, widgets.SystemIcon.run)
    wear(commands, RENDER, widgets.SystemIcon.print)
    wear(commands, ABOUT, widgets.SystemIcon.info)

    let have_bar: bool = platform.Capability.toolbar.available()
    if have_bar { window.set_toolbar(commands)? }

    // ---------------------------------------------------- the navigator

    var navigator: widgets.Container = new widgets.Container()
    var nav_head: widgets.Label = widgets.Label.of("Database Navigator")?
    // A real tree. This was a one-column table with the indentation drawn in
    // by hand until `cortado.widgets.OutlineView` existed — see ui/navigator.b
    // and this directory's README for what that cost and what it proved.
    let have_tree: bool = widgets.WidgetKind.outline_view.available()
    var nav_rows: widgets.OutlineView = new widgets.OutlineView()
    var no_tree: widgets.Label = widgets.Label.of("")?
    navigator.add(nav_head)?
    if have_tree {
        nav_rows = widgets.OutlineView.of(["Connection"])?
        nav_rows.set_column_width(0, 340.0)?
        nav_rows.set_source(tree)?
        navigator.add(nav_rows)?
    } else {
        no_tree.set_text("This platform has no outline view, so there is no navigator. UIKit's tree is a collection-view layout rather than a control.")?
        navigator.add(no_tree)?
    }

    // ------------------------------------------------------- the editor

    var editor: widgets.Container = new widgets.Container()
    let have_tabs: bool = widgets.WidgetKind.tab_view.available()
    var tabs: widgets.TabView = new widgets.TabView()

    // Data
    var data_page: widgets.Container = new widgets.Container()
    var hunt: widgets.SearchField = widgets.SearchField.of("Filter these rows")?
    var rows: widgets.Table = widgets.Table.of(["(nothing open)"])?
    var counted: widgets.Label = widgets.Label.of("Open a table in the navigator")?
    data_page.add(hunt)?
    data_page.add(rows)?
    data_page.add(counted)?

    // Columns
    var columns_page: widgets.Container = new widgets.Container()
    var columns: widgets.Table = widgets.Table.of(
        ["#", "Name", "Type", "Not null", "Default", "Key"])?
    columns.set_column_width(0, 34.0)?
    columns.set_column_width(1, 170.0)?
    columns.set_column_width(2, 100.0)?
    columns.set_column_width(3, 72.0)?
    columns.set_column_width(4, 100.0)?
    columns.set_column_width(5, 44.0)?
    columns_page.add(columns)?

    // DDL
    var ddl_page: widgets.Container = new widgets.Container()
    var ddl: widgets.TextArea = widgets.TextArea.of("")?
    ddl_page.add(ddl)?

    // SQL editor — a statement above, its results below, which is the one
    // place a second split view earns its keep.
    var sql_page: widgets.Container = new widgets.Container()
    var sql: widgets.TextArea = widgets.TextArea.of(
        "SELECT name, origin, score, roasted_on\n  FROM beans\n WHERE roasted_on >= :since\n ORDER BY roasted_on")?
    var since_says: widgets.Label = widgets.Label.of(":since")?
    var since: widgets.DatePicker = new widgets.DatePicker()
    let have_day: bool = widgets.WidgetKind.date_picker.available()
    // 2026-08-01 00:00 UTC, floored to the day the way every date picker here
    // stores one. Written as the number rather than built from a calendar
    // because a date picker holds seconds and this is the only place a date
    // is named — and checked, because the first one written here was
    // 2026-07-28 and the query it filtered came back with every row, which
    // looks exactly like a parameter that was never bound.
    let august: f64 = 1785542400.0
    if have_day { since = widgets.DatePicker.of(august)? }
    var go: widgets.Button = widgets.Button.of("Execute")?
    var answer: widgets.Table = widgets.Table.of(["(not run yet)"])?
    var said: widgets.Label = widgets.Label.of("")?

    var sql_top: widgets.Container = new widgets.Container()
    var sql_foot: widgets.Container = new widgets.Container()
    sql_top.add(sql)?
    sql_top.add(since_says)?
    if have_day { sql_top.add(since)? }
    sql_top.add(go)?
    sql_foot.add(answer)?
    sql_foot.add(said)?

    let have_split: bool = widgets.WidgetKind.split_view.available()
    var sql_split: widgets.SplitView = new widgets.SplitView()
    if have_split {
        // Stacked: the statement above, the answer below. The same control as
        // the one holding the navigator, turned ninety degrees.
        sql_split = widgets.SplitView.of(true)?
        sql_split.add(sql_top)?
        sql_split.add(sql_foot)?
        sql_page.add(sql_split)?
    } else {
        sql_page.add(sql_top)?
        sql_page.add(sql_foot)?
    }

    // Report
    var report_page: widgets.Container = new widgets.Container()
    var ink_says: widgets.Label = widgets.Label.of("Accent")?
    var ink: widgets.ColorWell = new widgets.ColorWell()
    let have_ink: bool = widgets.WidgetKind.color_well.available()
    if have_ink { ink = widgets.ColorWell.of(state.accent)? }
    var draw: widgets.Button = widgets.Button.of("Render")?
    let have_web: bool = widgets.WebView.offered()
    var page: widgets.WebView = new widgets.WebView()
    var no_web: widgets.Label = widgets.Label.of("")?
    report_page.add(ink_says)?
    if have_ink { report_page.add(ink)? }
    report_page.add(draw)?
    if have_web {
        page = widgets.WebView.of()?
        report_page.add(page)?
    } else {
        no_web.set_text("No browser engine on this platform, so there is no report. WKWebView is part of macOS and iOS; GTK's is a separate library and Windows' is a redistributable.")?
        report_page.add(no_web)?
    }

    if have_tabs {
        tabs = widgets.TabView.of()?
        tabs.add_page(data_page, "Data")?
        tabs.add_page(columns_page, "Columns")?
        tabs.add_page(ddl_page, "DDL")?
        tabs.add_page(sql_page, "SQL")?
        tabs.add_page(report_page, "Report")?
        editor.add(tabs)?
    } else {
        editor.add(data_page)?
        editor.add(sql_page)?
    }

    // -------------------------------------------------------- the split

    var split: widgets.SplitView = new widgets.SplitView()
    if have_split {
        split = widgets.SplitView.of(false)?
        split.add(navigator)?
        split.add(editor)?
        root.add(split)?
    } else {
        root.add(navigator)?
        root.add(editor)?
    }

    var status: widgets.Label = widgets.Label.of("")?
    var facts: widgets.Button = widgets.Button.of("Connection")?
    root.add(status)?
    root.add(facts)?
    status.set_text("{link.server()?} — {link.label()?}")?

    // ------------------------------------------------------- the layout

    let content: geometry.Size = window.content_size()?

    // Rebuilt rather than adjusted, and rebuilt on every divider drag,
    // because a divider's position is an *input* to the arranger: the subtree
    // in each pane has to be solved against the width that pane actually got.
    let arrange: fn() = fn() {
        var sheet: widgets.WidgetLayout = new widgets.WidgetLayout()
        var body: layout.FlexLayout = layout.FlexLayout.column(8.0)
        body.set_padding(geometry.EdgeInsets.all(10.0))
        body.set_align(geometry.Align.stretch)
        var frame: layout.LayoutNode = sheet.group("window", root, body)

        var nav_stack: layout.FlexLayout = layout.FlexLayout.column(6.0)
        nav_stack.set_align(geometry.Align.stretch)
        var left: layout.LayoutNode = sheet.group("navigator", navigator, nav_stack)
        var head_node: layout.LayoutNode = sheet.leaf("nav_head", nav_head)
        head_node.spec = layout.LayoutSpec.tall(18.0)
        left.add(head_node)
        var tree_node: layout.LayoutNode = if have_tree { sheet.leaf("nav_rows", nav_rows) }
                                            else { sheet.leaf("no_tree", no_tree) }
        tree_node.spec = layout.LayoutSpec.flexible(1.0)
        left.add(tree_node)

        var data_node: layout.LayoutNode = page_node(sheet, "data", data_page)
        data_node.add(sheet.leaf("hunt", hunt))
        var grid_node: layout.LayoutNode = sheet.leaf("rows", rows)
        grid_node.spec = layout.LayoutSpec.flexible(1.0)
        data_node.add(grid_node)
        data_node.add(sheet.leaf("counted", counted))

        var columns_node: layout.LayoutNode = page_node(sheet, "columns", columns_page)
        var cols_grid: layout.LayoutNode = sheet.leaf("columns", columns)
        cols_grid.spec = layout.LayoutSpec.flexible(1.0)
        columns_node.add(cols_grid)

        var ddl_node: layout.LayoutNode = page_node(sheet, "ddl", ddl_page)
        var ddl_text: layout.LayoutNode = sheet.leaf("ddl", ddl)
        ddl_text.spec = layout.LayoutSpec.flexible(1.0)
        ddl_node.add(ddl_text)

        // --- the SQL editor, split top and bottom
        var top_stack: layout.FlexLayout = layout.FlexLayout.column(8.0)
        top_stack.set_padding(geometry.EdgeInsets.all(8.0))
        top_stack.set_align(geometry.Align.stretch)
        var top_node: layout.LayoutNode = sheet.group("sql_top", sql_top, top_stack)
        var sql_text: layout.LayoutNode = sheet.leaf("sql", sql)
        sql_text.spec = layout.LayoutSpec.flexible(1.0)
        top_node.add(sql_text)
        var bar_row: layout.FlexLayout = layout.FlexLayout.row(8.0)
        var bar_node: layout.LayoutNode = sheet.spacer("sql_bar", bar_row)
        bar_node.spec = layout.LayoutSpec.tall(26.0)
        var since_label: layout.LayoutNode = sheet.leaf("since_says", since_says)
        since_label.spec = layout.LayoutSpec.fixed(48.0, 20.0)
        bar_node.add(since_label)
        if have_day {
            var day_node: layout.LayoutNode = sheet.leaf("since", since)
            day_node.spec = layout.LayoutSpec.fixed(150.0, 24.0)
            bar_node.add(day_node)
        }
        var spring: layout.LayoutNode = sheet.spacer("spring", layout.FlexLayout.row(0.0))
        spring.spec = layout.LayoutSpec.flexible(1.0)
        bar_node.add(spring)
        var go_node: layout.LayoutNode = sheet.leaf("go", go)
        go_node.spec = layout.LayoutSpec.fixed(90.0, 24.0)
        bar_node.add(go_node)
        top_node.add(bar_node)

        var foot_stack: layout.FlexLayout = layout.FlexLayout.column(6.0)
        foot_stack.set_padding(geometry.EdgeInsets.all(8.0))
        foot_stack.set_align(geometry.Align.stretch)
        var foot_node: layout.LayoutNode = sheet.group("sql_foot", sql_foot, foot_stack)
        var answer_node: layout.LayoutNode = sheet.leaf("answer", answer)
        answer_node.spec = layout.LayoutSpec.flexible(1.0)
        foot_node.add(answer_node)
        foot_node.add(sheet.leaf("said", said))

        var sql_node: layout.LayoutNode = page_node(sheet, "sql", sql_page)
        if have_split {
            match sql_split.split_layout() {
                err(problem) => { io.println("{problem.kind}: {problem.msg}") }
                ok(divided) => {
                    var pair: layout.LayoutNode = sheet.group("sql_split", sql_split, divided)
                    pair.spec = layout.LayoutSpec.flexible(1.0)
                    pair.add(top_node)
                    pair.add(foot_node)
                    sql_node.add(pair)
                }
            }
        } else {
            top_node.spec = layout.LayoutSpec.flexible(1.0)
            foot_node.spec = layout.LayoutSpec.flexible(1.0)
            sql_node.add(top_node)
            sql_node.add(foot_node)
        }

        var report_node: layout.LayoutNode = page_node(sheet, "report", report_page)
        var ink_row: layout.FlexLayout = layout.FlexLayout.row(8.0)
        var ink_node: layout.LayoutNode = sheet.spacer("ink_row", ink_row)
        ink_node.spec = layout.LayoutSpec.tall(28.0)
        var ink_label: layout.LayoutNode = sheet.leaf("ink_says", ink_says)
        ink_label.spec = layout.LayoutSpec.fixed(50.0, 20.0)
        ink_node.add(ink_label)
        if have_ink {
            var well_node: layout.LayoutNode = sheet.leaf("ink", ink)
            well_node.spec = layout.LayoutSpec.fixed(46.0, 24.0)
            ink_node.add(well_node)
        }
        var draw_node: layout.LayoutNode = sheet.leaf("draw", draw)
        draw_node.spec = layout.LayoutSpec.fixed(90.0, 24.0)
        ink_node.add(draw_node)
        report_node.add(ink_node)
        var web_node: layout.LayoutNode = if have_web { sheet.leaf("page", page) }
                                           else { sheet.leaf("no_web", no_web) }
        web_node.spec = layout.LayoutSpec.flexible(1.0)
        report_node.add(web_node)

        var right: layout.LayoutNode = sheet.leaf("editor", editor)
        if have_tabs {
            var pages: layout.FillLayout = new layout.FillLayout()
            var tab_node: layout.LayoutNode = sheet.group("tabs", tabs, pages)
            tab_node.spec = layout.LayoutSpec.flexible(1.0)
            tab_node.add(data_node)
            tab_node.add(columns_node)
            tab_node.add(ddl_node)
            tab_node.add(sql_node)
            tab_node.add(report_node)
            var one: layout.FillLayout = new layout.FillLayout()
            right = sheet.group("editor", editor, one)
            right.add(tab_node)
        } else {
            var both: layout.FlexLayout = layout.FlexLayout.column(8.0)
            both.set_align(geometry.Align.stretch)
            right = sheet.group("editor", editor, both)
            data_node.spec = layout.LayoutSpec.flexible(1.0)
            sql_node.spec = layout.LayoutSpec.flexible(1.0)
            right.add(data_node)
            right.add(sql_node)
        }

        if have_split {
            match split.split_layout() {
                err(problem) => { io.println("{problem.kind}: {problem.msg}") }
                ok(divided) => {
                    var pair: layout.LayoutNode = sheet.group("split", split, divided)
                    pair.spec = layout.LayoutSpec.flexible(1.0)
                    pair.add(left)
                    pair.add(right)
                    frame.add(pair)
                }
            }
        } else {
            left.spec = layout.LayoutSpec.wide(SIDEBAR)
            right.spec = layout.LayoutSpec.flexible(1.0)
            frame.add(left)
            frame.add(right)
        }

        var foot: layout.FlexLayout = layout.FlexLayout.row(8.0)
        var bottom: layout.LayoutNode = sheet.spacer("foot", foot)
        bottom.spec = layout.LayoutSpec.tall(24.0)
        var status_node: layout.LayoutNode = sheet.leaf("status", status)
        status_node.spec = layout.LayoutSpec.flexible(1.0)
        bottom.add(status_node)
        var facts_node: layout.LayoutNode = sheet.leaf("facts", facts)
        facts_node.spec = layout.LayoutSpec.fixed(110.0, 22.0)
        bottom.add(facts_node)
        frame.add(bottom)

        var solver: layout.Solver = new layout.Solver(sheet)
        match solver.solve(frame, geometry.Rect.at(geometry.Point.zero(), content)) {
            ok(done) => {}
            err(problem) => { io.println("layout: {problem.kind}: {problem.msg}") }
        }
        match sheet.apply(frame) {
            ok(done) => {}
            err(problem) => { io.println("apply: {problem.kind}: {problem.msg}") }
        }
    }

    // ------------------------------------------------------- filling in

    let retree: fn() = fn() {
        if !have_tree { return }
        // The navigator forgets its nodes and the control asks again from the
        // root. Node numbers are not reused, so a selection cannot end up
        // pointing at a different object than the one a person clicked.
        state.tree.forget()
        match nav_rows.reload() {
            ok(built) => {}
            err(problem) => { status.set_text("{problem.kind}: {problem.msg}") }
        }
        let said: string = state.tree.trouble_says()
        if said != "" { status.set_text(said) }
    }

    /// Shows the rows of whatever is selected, filtered by the search field.
    let refilter: fn() = fn() {
        var needle: string = ""
        match hunt.value() {
            ok(typed) => { needle = typed }
            err(problem) => {}
        }
        fill(rows, state.data.filtered(needle), "(nothing open)")
    }

    /// Opens one object: its rows, its columns, and its DDL.
    let open_object: fn(DbObject) = fn(node: DbObject) {
        state.chosen = node.name()
        state.kind = node.kind()

        if node.kind().has_rows() {
            match state.link.rows_of(node, PAGE) {
                err(problem) => {
                    counted.set_text("{problem.kind}: {problem.msg}")
                    state.data = Grid.empty()
                }
                ok(found) => {
                    var note: string = "{found.row_count()} rows"
                    if !found.is_complete() {
                        match state.link.count_of(node) {
                            ok(total) => { note = "{found.row_count()} of {total} rows" }
                            err(problem) => { note = "{found.row_count()} rows, and there are more" }
                        }
                    }
                    counted.set_text("{node.name()} — {note}")
                    state.data = found
                }
            }
        } else {
            state.data = Grid.empty()
            counted.set_text("a {node.kind().name()} has no rows of its own")
        }
        refilter()

        match state.link.columns_of(node) {
            err(problem) => { fill(columns, Grid.empty(), "(no columns)") }
            ok(shape) => { fill(columns, shape, "(no columns)") }
        }
        match state.link.ddl_of(node) {
            err(problem) => { ddl.set_value("") }
            ok(text) => {
                if text == "" {
                    ddl.set_value("The database kept no CREATE statement for this {node.kind().name()}.")
                } else {
                    ddl.set_value(text)
                }
            }
        }
        status.set_text("{node.kind().mark()} {node.name()} — {node.kind().name()}")
    }

    /// Runs whatever is in the SQL editor, binding `:since` from the picker.
    let execute: fn() = fn() {
        var text: string = ""
        match sql.value() {
            ok(typed) => { text = typed }
            err(problem) => { said.set_text("{problem.kind}: {problem.msg}") }
        }
        var day: string = "1970-01-01"
        if have_day {
            match since.day() {
                ok(seconds) => {
                    match calendar.DateTime.from_epoch_seconds(seconds as int) {
                        ok(moment) => { day = moment.to_date_string() }
                        err(problem) => {}
                    }
                }
                err(problem) => {}
            }
        }
        // `:since` is spliced rather than bound, and that is a decision worth
        // naming: the text is a whole script a person typed, so it may hold
        // any number of statements and cask has no say in how many parameters
        // they carry. What makes the splice safe is that the value never came
        // from text — it is a day number out of a date picker, turned into
        // eight digits and two dashes here.
        let ready: string = text.replace(":since", "'{day}'")
        match state.link.run(ready, PAGE) {
            err(problem) => { said.set_text("{problem.kind}: {problem.msg}") }
            ok(found) => {
                state.answer = found
                if state.answer.column_count() == 0 {
                    said.set_text("that statement ran and returned no columns")
                    return
                }
                fill(answer, state.answer, "(not run yet)")
                var note: string = "{state.answer.row_count()} rows, :since = {day}"
                if !state.answer.is_complete() {
                    note = "{state.answer.row_count()} rows and the reading stopped there, :since = {day}"
                }
                said.set_text(note)
            }
        }
    }

    /// Renders whichever grid was last looked at, as a page.
    let render: fn() = fn() {
        if !have_web { return }
        if have_ink {
            match ink.color() {
                ok(picked) => { state.accent = picked }
                err(problem) => {}
            }
        }
        var subject: Grid = state.data
        var title: string = state.chosen
        if state.answer.row_count() > 0 {
            subject = state.answer
            title = "query"
        }
        if title == "" { title = "nothing open" }
        match page.load_html(new Report().page(title, subject, state.accent), "") {
            ok(loading) => {}
            err(problem) => { status.set_text("{problem.kind}: {problem.msg}") }
        }
    }

    // ------------------------------------------------------- the wiring

    app.router.on(host.Handle.none(), events.EventKind.command,
        fn(event: events.UiEvent) {
            if event.token == REFRESH { retree() }
            if event.token == EXECUTE {
                execute()
                if have_tabs { tabs.set_page(TAB_SQL) }
            }
            if event.token == RENDER {
                render()
                if have_tabs { tabs.set_page(TAB_REPORT) }
            }
            if event.token == ABOUT { show_facts(state, facts, status) }
        })

    // The event carries the **node**, not a row — which is the difference a
    // tree needs: a row number changes every time something above it opens,
    // and a node does not. Selecting is only selecting now; the triangle
    // opens a folder, which is the control's own job.
    if have_tree {
        app.router.on(nav_rows.handle(), events.EventKind.selection,
            fn(event: events.UiEvent) {
                match state.tree.object_at(event.index as int) {
                    none => {}
                    some(node) => {
                        open_object(node)
                        if have_tabs && node.kind().has_rows() {
                            tabs.set_page(TAB_DATA)
                        }
                    }
                }
            })
    }

    app.router.on(hunt.handle(), events.EventKind.value_changed,
        fn(event: events.UiEvent) { refilter() })
    app.router.on(hunt.handle(), events.EventKind.text_commit,
        fn(event: events.UiEvent) { refilter() })
    app.router.on(go.handle(), events.EventKind.activate,
        fn(event: events.UiEvent) { execute() })
    app.router.on(draw.handle(), events.EventKind.activate,
        fn(event: events.UiEvent) { render() })
    app.router.on(facts.handle(), events.EventKind.activate,
        fn(event: events.UiEvent) { show_facts(state, facts, status) })

    if have_ink {
        app.router.on(ink.handle(), events.EventKind.value_changed,
            fn(event: events.UiEvent) { render() })
    }
    if have_day {
        app.router.on(since.handle(), events.EventKind.value_changed,
            fn(event: events.UiEvent) { execute() })
    }
    if have_split {
        app.router.on(split.handle(), events.EventKind.value_changed,
            fn(event: events.UiEvent) {
                state.divider = event.index as f64
                arrange()
            })
        app.router.on(sql_split.handle(), events.EventKind.value_changed,
            fn(event: events.UiEvent) {
                state.editor = event.index as f64
                arrange()
            })
    }

    // ---------------------------------------------------------------- go

    // Laid out first, *then* the dividers, then laid out again — and the
    // order is the whole point. Every platform here re-divides a split view's
    // panes when the control itself is resized, so a divider written before
    // the control has its final frame is not the divider a moment later. The
    // first pass gives each split view its real size; the second is the one
    // whose pane widths are true.
    arrange()
    if have_split {
        split.set_divider(state.divider)?
        sql_split.set_divider(state.editor)?
        arrange()
    }

    retree()
    if have_tree {
        // The connection node open, the way DBeaver opens the one you just
        // made. Opened from the top down and one level at a time, because a
        // node inside a shut parent is not one the control has.
        let first: int = state.tree.child_at(widgets.OutlineView.root(), 0)
        if first != 0 {
            nav_rows.expand(first)?
            nav_rows.select(first)?
        }
    }

    io.println("cask: {link.label()?} via {link.server()?}")
    io.println("  drivers={drivers.count()} toolbar={have_bar} split={have_split} tabs={have_tabs}")
    io.println("  day={have_day} colour={have_ink} web={have_web}")
    if !showing {
        // What a person would see in the navigator, and what opening a table
        // put on the Data tab. The control tree below says the window is laid
        // out; these say the database was read — which is the half a dump of
        // widgets cannot show, because a table's rows are not controls.
        io.println("-- the navigator --")
        // Walked through the *source*, not the control, and the difference is
        // the point: this is what a person would see if they opened every
        // node, and what the control shows is whichever of these are open.
        show_tree(state.tree, widgets.OutlineView.root(), 0)
        match find_node(state.tree, widgets.OutlineView.root(), "beans") {
            none => { io.println("-- no table called beans --") }
            some(node) => {
                open_object(node)
                io.println("-- opening a table --")
                io.println("  {state.data.column_count()} columns, {state.data.row_count()} rows")
                io.println("  titles: {joined(state.data.column_titles())}")
                io.println("  row 7: {joined(row_of(state.data, 7))}")
                io.println("  filtered to 'ethiopia': {state.data.filtered("ethiopia").row_count()} rows")
            }
        }
        execute()
        io.println("-- running the editor's statement --")
        io.println("  {state.answer.column_count()} columns, {state.answer.row_count()} rows")
        io.println("  titles: {joined(state.answer.column_titles())}")
        // The editor's own message, which names the day `:since` became — so
        // the golden shows the parameter and not only its effect. The table
        // has eight rows and this answers seven, which is the earliest one
        // falling outside the date the picker holds.
        io.println("  it said: {said.text().or("?")}")

        io.print(widgets.WidgetDump.of(root)?)
        link.close()?
        app.shutdown()
        return ok(true)
    }

    window.show()?
    app.run()
    link.close()?
    app.shutdown()
    return ok(true)
}

/// Puts a system icon on a command, if this platform has that one.
///
/// Asking first is the whole point: `set_icon` refuses a role the platform
/// cannot draw, and a program that ignored the refusal would show a blank
/// where a word would have done. The command keeps its title either way, so
/// the toolbar is usable on a host with no icon for it at all.
fn wear(commands: surface.Menu, token: int, icon: widgets.SystemIcon) {
    if !icon.available() { return }
    match commands.set_icon(token, icon) {
        ok(worn) => {}
        err(problem) => {}
    }
}

/// Prints one node and everything under it, indented.
///
/// The dump's view of the tree. It asks the *source* rather than the control,
/// because the control is showing only what is open and the golden is about
/// whether the database was read — which is the half a dump of widgets cannot
/// show, since a tree's nodes are not controls.
fn show_tree(tree: Navigator, node: int, depth: int) {
    var at: int = 0
    for at < tree.child_count(node) {
        let child: int = tree.child_at(node, at)
        var pad: string = ""
        var step: int = 0
        for step < depth {
            pad = "{pad}    "
            step = step + 1
        }
        io.println("  {pad}{tree.cell(child, 0)}")
        show_tree(tree, child, depth + 1)
        at = at + 1
    }
}

/// The first node under `node` whose object is called `name`, at any depth.
fn find_node(tree: Navigator, node: int, name: string) -> Option<DbObject> {
    var at: int = 0
    for at < tree.child_count(node) {
        let child: int = tree.child_at(node, at)
        match tree.object_at(child) {
            none => {}
            some(thing) => {
                if thing.name() == name { return some(thing) }
            }
        }
        match find_node(tree, child, name) {
            some(deeper) => { return some(deeper) }
            none => {}
        }
        at = at + 1
    }
    return none
}

/// One row of a grid, as a list. Only the dump uses it: a person reads rows
/// off the screen.
fn row_of(grid: Grid, row: int) -> List<string> {
    var out: List<string> = []
    var at: int = 0
    for at < grid.column_count() {
        out.push(grid.cell(row, at))
        at = at + 1
    }
    return move out
}

/// Words with a bar between them. Beans has no `+` for strings and no `join`
/// on a list, and a golden wants one line.
fn joined(words: List<string>) -> string {
    var out: string = ""
    for word: string in words {
        if out == "" { out = word } else { out = "{out} | {word}" }
    }
    return out
}

/// A tab page's node: a column with its own padding, which is what keeps the
/// five pages from each writing the same three lines.
fn page_node(sheet: widgets.WidgetLayout, name: string,
    holder: widgets.Container) -> layout.LayoutNode {
    var stack: layout.FlexLayout = layout.FlexLayout.column(8.0)
    stack.set_padding(geometry.EdgeInsets.all(10.0))
    stack.set_align(geometry.Align.stretch)
    return sheet.group(name, holder, stack)
}

/// Points a table at a grid, with columns titled and sized to fit.
///
/// Column widths are the one thing the solver cannot choose: it knows how
/// wide the table is and nothing about what is in it. Eight points a
/// character, floored at 60 and capped at 220, which is a guess — but a guess
/// made from the data rather than from the column's position.
fn fill(control: widgets.Table, shown: Grid, empty: string) {
    var titles: List<string> = shown.column_titles()
    if titles.len() == 0 { titles = [empty] }
    match control.set_columns(titles.len()) {
        ok(set) => {}
        err(problem) => { return }
    }
    var at: int = 0
    for at < titles.len() {
        control.set_column_title(at, titles[at])
        var points: f64 = (shown.widest(at, 28) as f64) * 8.0
        if points < 60.0 { points = 60.0 }
        if points > 220.0 { points = 220.0 }
        control.set_column_width(at, points)
        at = at + 1
    }
    control.set_source(shown)
    control.reload()
}

/// What the database says about itself, in a popover.
///
/// Free-form lines, because no two databases agree on what is worth saying —
/// SQLite answers page size and encoding, a server would answer uptime and
/// character set — and a popover that only prints lines is what lets the
/// driver decide.
fn show_facts(state: Session, anchor: widgets.Widget, status: widgets.Label) {
    var lines: List<string> = []
    match state.link.facts() {
        // Copied out rather than moved: a `match` arm borrows what it binds,
        // and a driver's own list is not this function's to take.
        ok(said) => {
            for line: string in said { lines.push(line) }
        }
        err(problem) => { lines.push("{problem.kind}: {problem.msg}") }
    }

    if !platform.Capability.popover.available() {
        // No popover here: the same lines go where there is room for them,
        // which is the status line. Saying nothing would be worse.
        var one: string = ""
        for line: string in lines {
            one = "{one}{line}   "
        }
        status.set_text(one)
        return
    }

    var inside: widgets.Container = new widgets.Container()
    var sheet: widgets.WidgetLayout = new widgets.WidgetLayout()
    var stack: layout.StackLayout = layout.StackLayout.column(4.0)
    stack.set_padding(geometry.EdgeInsets.all(12.0))
    stack.set_align(geometry.Align.stretch)
    var panel: layout.LayoutNode = sheet.group("facts", inside, stack)

    var at: int = 0
    for line: string in lines {
        match widgets.Label.of(line) {
            err(problem) => {}
            ok(said) => {
                match inside.add(said) {
                    ok(added) => { panel.add(sheet.leaf("line{at}", said)) }
                    err(problem) => {}
                }
            }
        }
        at = at + 1
    }

    let tall: f64 = 24.0 + (lines.len() as f64) * 18.0
    var solver: layout.Solver = new layout.Solver(sheet)
    match solver.solve(panel, geometry.Rect.of(0.0, 0.0, 300.0, tall)) {
        ok(done) => {}
        err(problem) => { return }
    }
    match sheet.apply(panel) {
        ok(done) => {}
        err(problem) => { return }
    }

    match surface.Popover.of(inside, 300.0, tall) {
        err(problem) => { status.set_text("{problem.kind}: {problem.msg}") }
        ok(shown) => {
            match shown.show(anchor, surface.Edge.above) {
                ok(up) => {}
                err(problem) => { status.set_text("{problem.kind}: {problem.msg}") }
            }
        }
    }
}

fn main() {
    var target: string = ""
    var showing: bool = true
    for arg: string in os.args() {
        // A word starting with two dashes is a switch, even one this program
        // does not know. Treating an unknown switch as a file name is how
        // `cask --help` answers "unable to open database file".
        if arg.starts_with("--") {
            if arg == "--dump" { showing = false }
        } else {
            target = arg
        }
    }
    match run(target, showing) {
        ok(done) => {}
        err(problem) => { io.println("{problem.kind}: {problem.msg}") }
    }
}
