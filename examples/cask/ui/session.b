// What the window is looking at, and everything it does when something is
// clicked.
package ui

import cortado.component
import cortado.widgets
import cortado.events
import std.calendar
import {ClosedConnection, Connection, DbObject, Grid, ObjectKind} from cask.engine

/// The state of one window, and its handlers.
///
/// **This is where the screen's behaviour went when its shape became markup.**
/// `site/browser.bx` says there is a table here and a split view there;
/// everything about what goes *in* them is below, because a table's rows and a
/// tab's labels are data and markup does not carry data.
///
/// A class rather than a pile of captured `var`s, and that was true before the
/// markup as well: every handler reads and writes the same selection, and a
/// closure captures a binding rather than a place.
///
/// The controls are held rather than looked up each time. They are the tree's
/// own widgets — `ChildHolder` owns them — so these are references to things
/// that outlive this object, not a second owner. A held control whose window
/// has gone answers a typed refusal, which is what the generation in a handle
/// is for.
pub class Session {
    pub link: Connection
    pub tree: Navigator
    pub chosen: string = ""
    pub kind: ObjectKind = ObjectKind.connection
    pub data: Grid = Grid.empty()
    pub answer: Grid = Grid.empty()
    pub divider: f64 = 250.0
    pub editor: f64 = 150.0
    pub accent: widgets.Rgba = widgets.Rgba {red: 47, green: 111, blue: 79, alpha: 255}
    /// 2026-08-01 00:00 UTC, floored to the day the way every date picker here
    /// stores one. Written as the number because a picker holds seconds — and
    /// checked, because the first one written here was 2026-07-28 and the
    /// query it filtered came back with every row, which looks exactly like a
    /// parameter that was never bound.
    pub since: f64 = 1785542400.0

    /// How many rows a read stops at. A browser that read a million-row table
    /// whole would be a browser nobody could open one with.
    priv page_size: int = 500

    // ---- the controls the markup built, by the key it gave them ----
    priv nav: widgets.OutlineView = new widgets.OutlineView()
    priv rows: widgets.Table = new widgets.Table()
    priv columns: widgets.Table = new widgets.Table()
    priv answer_grid: widgets.Table = new widgets.Table()
    priv tabs: widgets.TabView = new widgets.TabView()
    priv report: widgets.WebView = new widgets.WebView()
    priv hunt: widgets.SearchField = new widgets.SearchField()
    priv sql: widgets.TextArea = new widgets.TextArea()
    priv ddl: widgets.TextArea = new widgets.TextArea()
    priv counted: widgets.Label = new widgets.Label()
    priv said: widgets.Label = new widgets.Label()
    priv status: widgets.Label = new widgets.Label()
    priv ink: widgets.ColorWell = new widgets.ColorWell()
    priv day_picker: widgets.DatePicker = new widgets.DatePicker()
    priv split: widgets.SplitView = new widgets.SplitView()
    priv editor_split: widgets.SplitView = new widgets.SplitView()
    priv dressed: bool = false

    pub fn init(link: Connection, tree: Navigator) {
        self.link = link
        self.tree = tree
    }

    /// A session with nothing behind it, for `@inject`'s default.
    ///
    /// Every call on it refuses, because a `Connection` with no database
    /// refuses — which is the right answer for a screen that was shown before
    /// anything was opened, and better than a screen that cannot be built at
    /// all.
    pub static fn blank() -> Session {
        let nowhere: Connection = new ClosedConnection()
        return new Session(nowhere, new Navigator(nowhere))
    }

    // ---- what the markup could not carry ----

    /// Points every control at its data, once, after they exist.
    ///
    /// Everything here is a method on a widget class rather than an attribute,
    /// which is exactly why it is here and not in the markup: a table's rows
    /// are a *source*, a tab's labels are strings the strip draws, and a
    /// divider's position is a number. None of those is a shape.
    pub fn dress(stage: component.Stage) -> Result<bool> {
        self.keep(stage)
        self.dressed = true

        // The navigator. **A column is data too**, which is the thing this
        // conversion kept discovering: `<OutlineView />` builds a tree with no
        // columns, because how many columns a tree has and what they are
        // called is not a shape. `OutlineView.of(["Connection"])` used to say
        // it at construction; this says it here, with everything else the
        // markup could not carry.
        if widgets.WidgetKind.outline_view.available() {
            self.nav.set_columns(1)?
            self.nav.set_column_title(0, "Connection")?
            self.nav.set_column_width(0, 340.0)?
            self.nav.set_source(self.tree)?
        }

        // The five pages' names. A tab strip is not something markup
        // describes — the pages are containers and these are what is written
        // on them.
        if widgets.WidgetKind.tab_view.available() {
            self.tabs.set_label(0, "Data")?
            self.tabs.set_label(1, "Columns")?
            self.tabs.set_label(2, "DDL")?
            self.tabs.set_label(3, "SQL")?
            self.tabs.set_label(4, "Report")?
        }

        // A statement to start from, so the SQL page is not an empty box.
        self.sql.set_value("SELECT name, origin, score, roasted_on\n  FROM beans\n WHERE roasted_on >= :since\n ORDER BY roasted_on")?

        self.status.set_text(self.status_line())?
        self.retree()
        self.open_first()
        return ok(true)
    }

    /// Puts the dividers where the session wants them.
    ///
    /// **Separate from `dress`, and it has to be.** A split view refuses a
    /// divider outside its own width, and at the moment `on_mount` runs the
    /// control exists and has no frame yet — so every platform answers
    /// `out_of_range` to a number that is perfectly reasonable a moment later.
    /// The caller lays out, calls this, and lays out again; the first pass
    /// gives each split its real size and the second is the one whose pane
    /// widths are true.
    pub fn place_dividers() -> Result<bool> {
        if !widgets.WidgetKind.split_view.available() { return ok(true) }
        // **Which way a split view divides has no markup attribute**, so it is
        // set here with everything else the markup could not carry. It is the
        // one item on that list that feels like shape rather than data — a
        // stacked split and a side-by-side one are different pictures — and it
        // is here because `bx/vocabulary.json` has no word for it, not because
        // it belongs here. Worth an attribute; named rather than hidden.
        self.editor_split.set_stacked(true)?
        self.split.set_divider(self.divider)?
        self.editor_split.set_divider(self.editor)?
        return ok(true)
    }

    /// Keeps whichever of its controls the markup actually built.
    ///
    /// A `$if` that was not taken leaves no control, and the key answers
    /// `none` — which is the honest shape for a platform with no outline view
    /// or no browser engine. The field keeps its blank widget, and every call
    /// on that refuses rather than crashing.
    priv fn keep(stage: component.Stage) {
        match stage.widget("tree") {
            some(found) => { match found as? widgets.OutlineView { some(one) => { self.nav = one } none => {} } }
            none => {}
        }
        match stage.widget("rows") {
            some(found) => { match found as? widgets.Table { some(one) => { self.rows = one } none => {} } }
            none => {}
        }
        match stage.widget("columns") {
            some(found) => { match found as? widgets.Table { some(one) => { self.columns = one } none => {} } }
            none => {}
        }
        match stage.widget("answer") {
            some(found) => { match found as? widgets.Table { some(one) => { self.answer_grid = one } none => {} } }
            none => {}
        }
        match stage.widget("tabs") {
            some(found) => { match found as? widgets.TabView { some(one) => { self.tabs = one } none => {} } }
            none => {}
        }
        match stage.widget("page") {
            some(found) => { match found as? widgets.WebView { some(one) => { self.report = one } none => {} } }
            none => {}
        }
        match stage.widget("hunt") {
            some(found) => { match found as? widgets.SearchField { some(one) => { self.hunt = one } none => {} } }
            none => {}
        }
        match stage.widget("sql") {
            some(found) => { match found as? widgets.TextArea { some(one) => { self.sql = one } none => {} } }
            none => {}
        }
        match stage.widget("ddl") {
            some(found) => { match found as? widgets.TextArea { some(one) => { self.ddl = one } none => {} } }
            none => {}
        }
        match stage.widget("counted") {
            some(found) => { match found as? widgets.Label { some(one) => { self.counted = one } none => {} } }
            none => {}
        }
        match stage.widget("said") {
            some(found) => { match found as? widgets.Label { some(one) => { self.said = one } none => {} } }
            none => {}
        }
        match stage.widget("status") {
            some(found) => { match found as? widgets.Label { some(one) => { self.status = one } none => {} } }
            none => {}
        }
        match stage.widget("ink") {
            some(found) => { match found as? widgets.ColorWell { some(one) => { self.ink = one } none => {} } }
            none => {}
        }
        match stage.widget("since") {
            some(found) => { match found as? widgets.DatePicker { some(one) => { self.day_picker = one } none => {} } }
            none => {}
        }
        match stage.widget("split") {
            some(found) => { match found as? widgets.SplitView { some(one) => { self.split = one } none => {} } }
            none => {}
        }
        match stage.widget("editor_split") {
            some(found) => { match found as? widgets.SplitView { some(one) => { self.editor_split = one } none => {} } }
            none => {}
        }
    }

    // ---- what the window says about itself ----

    pub fn status_line() -> string {
        let where: string = self.link.server().or("nowhere")
        let what: string = self.link.label().or("nothing")
        return "{where} — {what}"
    }

    // ---- the handlers ----

    /// The navigator forgets its nodes and the control asks again from the
    /// root. Node numbers are not reused, so a selection cannot end up
    /// pointing at a different object than the one a person clicked.
    pub fn retree() {
        if !widgets.WidgetKind.outline_view.available() { return }
        self.tree.forget()
        match self.nav.reload() {
            ok(built) => {}
            err(problem) => { self.status.set_text("{problem.kind}: {problem.msg}").or(false) }
        }
        let said: string = self.tree.trouble_says()
        if said != "" { self.status.set_text(said).or(false) }
    }

    /// The connection node open, the way DBeaver opens the one you just made.
    /// From the top down and one level at a time, because a node inside a shut
    /// parent is not one the control has.
    priv fn open_first() {
        if !widgets.WidgetKind.outline_view.available() { return }
        let first: int = self.tree.child_at(widgets.OutlineView.root(), 0)
        if first == 0 { return }
        self.nav.expand(first).or(false)
        self.nav.select(first).or(false)
    }

    /// The event carries the **node**, not a row — which is the difference a
    /// tree needs: a row number changes every time something above it opens,
    /// and a node does not.
    pub fn picked(event: events.UiEvent) {
        match self.tree.object_at(event.index as int) {
            none => {}
            some(node) => {
                self.open_object(node)
                if widgets.WidgetKind.tab_view.available() && node.kind().has_rows() {
                    self.tabs.set_page(0).or(false)
                }
            }
        }
    }

    /// Shows the rows of whatever is selected, filtered by the search field.
    pub fn refilter() {
        let needle: string = self.hunt.value().or("")
        Session.fill(self.rows, self.data.filtered(needle), "(nothing open)")
    }

    /// Opens one object: its rows, its columns, and its DDL.
    pub fn open_object(node: DbObject) {
        self.chosen = node.name()
        self.kind = node.kind()

        if node.kind().has_rows() {
            match self.link.rows_of(node, self.page_size) {
                err(problem) => {
                    self.counted.set_text("{problem.kind}: {problem.msg}").or(false)
                    self.data = Grid.empty()
                }
                ok(found) => {
                    var note: string = "{found.row_count()} rows"
                    if !found.is_complete() {
                        match self.link.count_of(node) {
                            ok(total) => { note = "{found.row_count()} of {total} rows" }
                            err(problem) => { note = "{found.row_count()} rows, and there are more" }
                        }
                    }
                    self.counted.set_text("{node.name()} — {note}").or(false)
                    self.data = found
                }
            }
        } else {
            self.data = Grid.empty()
            self.counted.set_text("a {node.kind().name()} has no rows of its own").or(false)
        }
        self.refilter()

        match self.link.columns_of(node) {
            err(problem) => { Session.fill(self.columns, Grid.empty(), "(no columns)") }
            ok(shape) => { Session.fill(self.columns, shape, "(no columns)") }
        }
        match self.link.ddl_of(node) {
            err(problem) => { self.ddl.set_value("").or(false) }
            ok(text) => {
                if text == "" {
                    self.ddl.set_value("The database kept no CREATE statement for this {node.kind().name()}.").or(false)
                } else {
                    self.ddl.set_value(text).or(false)
                }
            }
        }
        self.status.set_text("{node.kind().mark()} {node.name()} — {node.kind().name()}").or(false)
    }

    /// Runs whatever is in the SQL editor, binding `:since` from the picker.
    pub fn execute() {
        let text: string = self.sql.value().or("")
        var day: string = "1970-01-01"
        if widgets.WidgetKind.date_picker.available() {
            match self.day_picker.day() {
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
        match self.link.run(ready, self.page_size) {
            err(problem) => { self.said.set_text("{problem.kind}: {problem.msg}").or(false) }
            ok(found) => {
                self.answer = found
                if self.answer.column_count() == 0 {
                    self.said.set_text("that statement ran and returned no columns").or(false)
                    return
                }
                Session.fill(self.answer_grid, self.answer, "(not run yet)")
                var note: string = "{self.answer.row_count()} rows, :since = {day}"
                if !self.answer.is_complete() {
                    note = "{self.answer.row_count()} rows and the reading stopped there, :since = {day}"
                }
                self.said.set_text(note).or(false)
            }
        }
        if widgets.WidgetKind.tab_view.available() { self.tabs.set_page(3).or(false) }
    }

    /// Renders whichever grid was last looked at, as a page.
    pub fn render() {
        if !widgets.WebView.offered() { return }
        if widgets.WidgetKind.color_well.available() {
            match self.ink.color() {
                ok(picked) => { self.accent = picked }
                err(problem) => {}
            }
        }
        var subject: Grid = self.data
        var title: string = self.chosen
        if self.answer.row_count() > 0 {
            subject = self.answer
            title = "query"
        }
        if title == "" { title = "nothing open" }
        match self.report.load_html(new Report().page(title, subject, self.accent), "") {
            ok(loading) => {}
            err(problem) => { self.status.set_text("{problem.kind}: {problem.msg}").or(false) }
        }
        if widgets.WidgetKind.tab_view.available() { self.tabs.set_page(4).or(false) }
    }

    /// What the database says about itself.
    ///
    /// Free-form lines, because no two databases agree on what is worth saying
    /// — SQLite answers page size and encoding, a server would answer uptime
    /// and a version string.
    pub fn show_facts() {
        match self.link.facts() {
            err(problem) => { self.status.set_text("{problem.kind}: {problem.msg}").or(false) }
            ok(lines) => {
                var said: string = ""
                for line: string in lines {
                    if said == "" { said = line }
                    else { said = "{said} · {line}" }
                }
                if said == "" { said = "this database says nothing about itself" }
                self.status.set_text(said).or(false)
            }
        }
    }

    /// What the SQL page's own line says, for the dump. A test reading the
    /// control would be reading the screen; this is the sentence the session
    /// wrote, which is the thing being checked.
    pub fn said_words() -> string {
        return self.said.text().or("")
    }

    pub fn divider_moved(event: events.UiEvent) {
        self.divider = event.index as f64
    }

    pub fn editor_moved(event: events.UiEvent) {
        self.editor = event.index as f64
    }

    /// Points a table at a grid, with columns titled and sized to fit.
    ///
    /// Column widths are the one thing the solver cannot choose: it knows how
    /// wide the table is and nothing about what is in it. Eight points a
    /// character, floored at 60 and capped at 220 — a guess, but one made from
    /// the data rather than from the column's position.
    priv static fn fill(control: widgets.Table, shown: Grid, empty: string) {
        var titles: List<string> = shown.column_titles()
        if titles.len() == 0 { titles = [empty] }
        match control.set_columns(titles.len()) {
            ok(set) => {}
            err(problem) => { return }
        }
        var at: int = 0
        for at < titles.len() {
            control.set_column_title(at, titles[at]).or(false)
            // Eight points a character of the widest value, floored and
            // capped. A guess, but one made from the data rather than from
            // the column's position.
            var points: f64 = (shown.widest(at, 28) as f64) * 8.0
            if points < 60.0 { points = 60.0 }
            if points > 220.0 { points = 220.0 }
            control.set_column_width(at, points).or(false)
            at = at + 1
        }
        control.set_source(shown).or(false)
        control.reload().or(false)
    }
}
