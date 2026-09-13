// Generated from screens/browser.bx by cortado. Do not edit.
//
// The <beans> block below is browser.bx's, copied through byte for byte; its
// own package line is blanked so every line after it keeps its number. The
// render method under it is the markup, as Builder calls.
// Change browser.bx and regenerate:
//
//     cortado generate screens/browser.bx
package screens

import {Builder, Component} from cortado.component
import {UiEvent} from cortado.events


//             

import cortado.component
import cortado.widgets
import cortado.events
import {view, inject, window, command} from cortado.annotations
import {Session} from cask.ui
import std.io

/// The whole of cask's window.
///
/// **Everything above the `<beans>` line replaced four hundred and fifty lines
/// of `main.b`**: every control built by hand, and an `arrange` closure that
/// wrote the layout tree out node by node and spec by spec, rebuilt from
/// scratch on every divider drag. What is there instead is `grow={1}` and
/// `height={26}` — the same solver, described rather than constructed.
///
/// What did **not** move is the part markup cannot carry, and this screen is
/// the clearest statement of that line cortado has: **a table's rows, an
/// outline's nodes, a tab's labels and a page's HTML are data.** The five
/// pages are laid out here and the words on their tabs are strings in
/// `Session.dress`, because a tab strip is not something markup describes.
///
/// Every `$if` in it is a control that is not on every platform, and each has
/// a sentence for where it is missing rather than a hole.
@view
@window(title: "cask", width: 1000.0, height: 660.0)
pub partial class Browser extends component.Component {
    /// Everything the window is looking at, and every handler it has.
    ///
    /// Injected rather than made here: `main.b` opens the database, and a
    /// screen that opened its own would be a screen that could not be shown
    /// against a different one.
    @inject pub work: Session = Session.blank()

    pub has_split: bool = false
    pub has_tabs: bool = false
    pub has_tree: bool = false
    pub has_day: bool = false
    pub has_ink: bool = false
    pub has_web: bool = false

    pub fn init() { super.init() }

    /// The window's commands, each on the method it runs.
    ///
    /// One declaration each, where there were two tables: five `Menu.add`
    /// rows with a token apiece in `main.b`, and a `router.on` handler
    /// matching those tokens back to these four calls. A command is not a
    /// control — it has a role the platform places it by, a shortcut the
    /// platform spells and an icon the platform may not have — so it is
    /// declared here rather than described in the markup above.
    @command(title: "Refresh", key: "mod+r", icon: "refresh")
    pub fn refresh_tree() { self.work.retree() }

    @command(title: "Execute", key: "mod+return", icon: "run")
    pub fn run_statement() { self.work.execute() }

    @command(title: "Report", key: "mod+p", icon: "print")
    pub fn render_report() { self.work.render() }

    @command(title: "Connection", key: "mod+i", icon: "info", separator: true)
    pub fn show_connection() { self.work.show_facts() }

    pub override fn on_init() {
        self.has_split = widgets.WidgetKind.split_view.available()
        self.has_tabs = widgets.WidgetKind.tab_view.available()
        self.has_tree = widgets.WidgetKind.outline_view.available()
        self.has_day = widgets.WidgetKind.date_picker.available()
        self.has_ink = widgets.WidgetKind.color_well.available()
        self.has_web = widgets.WebView.offered()
    }

    /// The data the markup could not carry: sources, columns, tab labels, the
    /// dividers. One place, run once, after the controls exist.
    pub override fn on_mount(stage: component.Stage) {
        // Reported rather than swallowed. A screen whose data never arrived
        // looks exactly like a screen with an empty database, and the first
        // version of this said `.or(false)` and spent twenty minutes looking
        // like the second.
        match self.work.dress(stage) {
            ok(done) => {}
            err(problem) => { io.println("cask: {problem.kind}: {problem.msg}") }
        }
    }

    pub fn no_tree() -> string {
        return "This platform has no outline view, so there is no navigator. UIKit's tree is a collection-view layout rather than a control."
    }

    pub fn no_web() -> string {
        return "No browser engine on this platform, so there is no report. WKWebView is part of macOS and iOS; GTK's is a separate library and Windows' is a redistributable."
    }

    pub fn no_tabs() -> string {
        return "This platform has no tab view, so the editor's five pages have nowhere to go."
    }

    pub fn no_split() -> string {
        return "This platform has no split view, so there is nowhere to put a navigator beside an editor."
    }
}

partial class Browser {
    pub override fn render(b: Builder) {
        b.open("VFlex")  // browser.bx:1
        b.number("spacing", (8) as f64)
        b.number("padding", (10) as f64)
        b.word("align", "stretch")
        if self.has_split {  // browser.bx:7
            b.open("SplitView")  // browser.bx:8
            b.key("{"split"}")
            b.number("grow", (1) as f64)
            b.on("change", fn(e: UiEvent) { self.work.divider_moved(e) })
            b.open("VFlex")  // browser.bx:11
            b.number("spacing", (6) as f64)
            b.word("align", "stretch")
            b.open("Label")  // browser.bx:12
            b.number("height", (18) as f64)
            b.text("Database Navigator")
            b.close()
            if self.has_tree {  // browser.bx:13
                b.open("OutlineView")  // browser.bx:14
                b.key("{"tree"}")
                b.number("grow", (1) as f64)
                b.on("select", fn(e: UiEvent) { self.work.picked(e) })
                b.close()
            }
            if !self.has_tree {  // browser.bx:17
                b.open("Label")  // browser.bx:18
                b.number("grow", (1) as f64)
                b.text("{self.no_tree()}")
                b.close()
            }
            b.close()
            b.open("VFlex")  // browser.bx:26
            b.key("{"editor"}")
            b.word("align", "stretch")
            if self.has_tabs {  // browser.bx:27
                b.open("TabView")  // browser.bx:28
                b.key("{"tabs"}")
                b.number("grow", (1) as f64)
                b.open("VFlex")  // browser.bx:33
                b.number("spacing", (8) as f64)
                b.number("padding", (10) as f64)
                b.word("align", "stretch")
                b.open("SearchField")  // browser.bx:34
                b.key("{"hunt"}")
                b.on("change", fn(e: UiEvent) { self.work.refilter() })
                b.on("commit", fn(e: UiEvent) { self.work.refilter() })
                b.close()
                b.open("Table")  // browser.bx:37
                b.key("{"rows"}")
                b.number("grow", (1) as f64)
                b.close()
                b.open("Label")  // browser.bx:38
                b.key("{"counted"}")
                b.text("Open a table in the navigator")
                b.close()
                b.close()
                b.open("VFlex")  // browser.bx:42
                b.number("spacing", (8) as f64)
                b.number("padding", (10) as f64)
                b.word("align", "stretch")
                b.open("Table")  // browser.bx:43
                b.key("{"columns"}")
                b.number("grow", (1) as f64)
                b.close()
                b.close()
                b.open("VFlex")  // browser.bx:47
                b.number("spacing", (8) as f64)
                b.number("padding", (10) as f64)
                b.word("align", "stretch")
                b.open("TextArea")  // browser.bx:48
                b.key("{"ddl"}")
                b.number("grow", (1) as f64)
                b.close()
                b.close()
                b.open("VFlex")  // browser.bx:53
                b.number("spacing", (8) as f64)
                b.number("padding", (10) as f64)
                b.word("align", "stretch")
                if self.has_split {  // browser.bx:54
                    b.open("SplitView")  // browser.bx:55
                    b.key("{"editor_split"}")
                    b.number("grow", (1) as f64)
                    b.on("change", fn(e: UiEvent) { self.work.editor_moved(e) })
                    b.open("VFlex")  // browser.bx:57
                    b.number("spacing", (8) as f64)
                    b.number("padding", (8) as f64)
                    b.word("align", "stretch")
                    b.open("TextArea")  // browser.bx:58
                    b.key("{"sql"}")
                    b.number("grow", (1) as f64)
                    b.close()
                    b.open("HFlex")  // browser.bx:59
                    b.number("spacing", (8) as f64)
                    b.number("height", (26) as f64)
                    b.open("Label")  // browser.bx:60
                    b.number("width", (48) as f64)
                    b.number("height", (20) as f64)
                    b.text(":since")
                    b.close()
                    if self.has_day {  // browser.bx:61
                        b.open("DatePicker")  // browser.bx:62
                        b.key("{"since"}")
                        b.number("width", (150) as f64)
                        b.number("height", (24) as f64)
                        b.number("day", (self.work.since) as f64)
                        b.on("change", fn(e: UiEvent) { self.work.execute() })
                        b.close()
                    }
                    b.open("Container")  // browser.bx:66
                    b.number("grow", (1) as f64)
                    b.close()
                    b.open("Button")  // browser.bx:67
                    b.number("width", (90) as f64)
                    b.number("height", (24) as f64)
                    b.on("click", fn(e: UiEvent) { self.work.execute() })
                    b.text("Execute")
                    b.close()
                    b.close()
                    b.close()
                    b.open("VFlex")  // browser.bx:73
                    b.number("spacing", (6) as f64)
                    b.number("padding", (8) as f64)
                    b.word("align", "stretch")
                    b.open("Table")  // browser.bx:74
                    b.key("{"answer"}")
                    b.number("grow", (1) as f64)
                    b.close()
                    b.open("Label")  // browser.bx:75
                    b.key("{"said"}")
                    b.text("")
                    b.close()
                    b.close()
                    b.close()
                }
                b.close()
                b.open("VFlex")  // browser.bx:82
                b.number("spacing", (8) as f64)
                b.number("padding", (10) as f64)
                b.word("align", "stretch")
                b.open("HFlex")  // browser.bx:83
                b.number("spacing", (8) as f64)
                b.number("height", (26) as f64)
                b.open("Label")  // browser.bx:84
                b.number("width", (60) as f64)
                b.number("height", (20) as f64)
                b.text("Accent")
                b.close()
                if self.has_ink {  // browser.bx:85
                    b.open("ColorWell")  // browser.bx:86
                    b.key("{"ink"}")
                    b.number("width", (60) as f64)
                    b.number("height", (24) as f64)
                    b.on("change", fn(e: UiEvent) { self.work.render() })
                    b.close()
                }
                b.open("Container")  // browser.bx:89
                b.number("grow", (1) as f64)
                b.close()
                b.open("Button")  // browser.bx:90
                b.number("width", (90) as f64)
                b.number("height", (24) as f64)
                b.on("click", fn(e: UiEvent) { self.work.render() })
                b.text("Render")
                b.close()
                b.close()
                if self.has_web {  // browser.bx:95
                    b.open("WebView")  // browser.bx:96
                    b.key("{"page"}")
                    b.number("grow", (1) as f64)
                    b.close()
                }
                if !self.has_web {  // browser.bx:98
                    b.open("Label")  // browser.bx:99
                    b.number("grow", (1) as f64)
                    b.text("{self.no_web()}")
                    b.close()
                }
                b.close()
                b.close()
            }
            if !self.has_tabs {  // browser.bx:105
                b.open("Label")  // browser.bx:106
                b.number("grow", (1) as f64)
                b.text("{self.no_tabs()}")
                b.close()
            }
            b.close()
            b.close()
        }
        if !self.has_split {  // browser.bx:111
            b.open("Label")  // browser.bx:112
            b.number("grow", (1) as f64)
            b.text("{self.no_split()}")
            b.close()
        }
        b.open("HFlex")  // browser.bx:115
        b.number("spacing", (8) as f64)
        b.number("height", (24) as f64)
        b.open("Label")  // browser.bx:116
        b.key("{"status"}")
        b.number("grow", (1) as f64)
        b.text("")
        b.close()
        b.open("Button")  // browser.bx:117
        b.number("width", (110) as f64)
        b.number("height", (24) as f64)
        b.on("click", fn(e: UiEvent) { self.work.show_facts() })
        b.text("Connection")
        b.close()
        b.close()
        b.close()
    }
}
