// Generated from site/shelf.bx by cortado. Do not edit.
//
// The <beans> block below is shelf.bx's, copied through byte for byte; its
// own package line is blanked so every line after it keeps its number. The
// render method under it is the markup, as Builder calls.
// Change shelf.bx and regenerate:
//
//     cortado generate site/shelf.bx
package site

import {Builder, Component} from cortado.component
import {UiEvent} from cortado.events


//          

import cortado.component
import cortado.events
import cortado.widgets
import {ShaderCanvas, ShapeCanvas} from cortado.gpu
import {view} from cortado.annotations

/// The order screen, showing one of every control cortado has.
///
/// **Nine of the thirty are not on every platform**, and every one of them is
/// wrapped in a `$if` here with a sentence for the other branch. That is the
/// shape a real screen takes: a control cortado will not substitute for you is
/// a control you decide about, and deciding once at the top of `init` is
/// cheaper than asking again in every branch.
///
/// Three of them are whole systems rather than controls — a tab view, a split
/// view and a browser engine — and none can be fully described in markup: a
/// tab's labels, a divider's position and a page's HTML are data. `main.b`
/// fills those in after the mount, the same way it fills the combo box, which
/// is the same rule rather than a special case.
@view
pub partial class Shelf extends component.Component {
    pub drink: string = "flat white"
    pub name: string = "Ada"
    pub shots: int = 2
    pub rush: bool = false
    pub warm: bool = false
    pub busy: bool = true
    pub day: f64 = 1767225600.0
    pub note: string = "no sugar"
    pub status: string = "Nothing ordered yet"
    /// The tint `<FancyButton>` is given. A field, not a literal, so the
    /// colour a screen computes reaches a control the way a number does.
    pub accent: string = "#8a4b2a"
    pub chosen: string = "2026-01-01, marker #3b82f6"

    /// Which sections are open. A shut disclosure still takes the room its
    /// children asked for unless the program stops describing them — which in
    /// markup is exactly this `$if`, and is why these are fields.
    pub words: bool = true
    pub choices: bool = true
    pub numbers: bool = false
    pub values: bool = false
    pub boxes: bool = false
    pub rows: bool = false
    pub systems: bool = false

    /// What this platform has. Asked once, at the top, rather than in every
    /// branch below.
    pub has_switch: bool = false
    pub has_segmented: bool = false
    pub has_level: bool = false
    pub has_spinner: bool = false
    pub has_color: bool = false
    pub has_group: bool = false
    pub has_tabs: bool = false
    pub has_split: bool = false
    pub has_web: bool = false
    pub has_tree: bool = false
    pub inventory: string = ""

    pub fn init() {
        super.init()
        self.has_switch = widgets.WidgetKind.switch.available()
        self.has_segmented = widgets.WidgetKind.segmented.available()
        self.has_level = widgets.WidgetKind.level_indicator.available()
        self.has_spinner = widgets.WidgetKind.spinner.available()
        self.has_color = widgets.WidgetKind.color_well.available()
        self.has_group = widgets.WidgetKind.group_box.available()
        self.has_tabs = widgets.WidgetKind.tab_view.available()
        self.has_split = widgets.WidgetKind.split_view.available()
        self.has_web = widgets.WidgetKind.web_view.available()
        self.has_tree = widgets.WidgetKind.outline_view.available()
        var here: int = 0
        for kind: widgets.WidgetKind in widgets.WidgetKind.all() {
            if kind.available() { here = here + 1 }
        }
        self.inventory = "{here} of {widgets.WidgetKind.all().len()} kinds on this platform"
    }

    pub fn pick(index: int) {
        if index == 1 { self.drink = "espresso" }
        else if index == 2 { self.drink = "cortado" }
        else { self.drink = "flat white" }
        self.request_render()
    }

    pub fn set_shots(event: events.UiEvent) {
        self.shots = event.index
        self.request_render()
    }

    pub fn set_day(event: events.UiEvent) {
        self.day = event.index as f64
        self.chosen = "day {event.index / 86400}, marker unchanged"
        self.request_render()
    }

    pub fn set_color(event: events.UiEvent) {
        let picked: widgets.Rgba = widgets.ColorWell.unpack(event.index)
        self.chosen = "marker {picked.show()}"
        self.request_render()
    }

    pub fn toggle_rush() {
        self.rush = !self.rush
        self.request_render()
    }

    pub fn toggle_warm(event: events.UiEvent) {
        self.warm = event.index == 1
        self.request_render()
    }

    pub fn toggle_words(event: events.UiEvent) {
        self.words = event.index == 1
        self.request_render()
    }

    pub fn toggle_choices(event: events.UiEvent) {
        self.choices = event.index == 1
        self.request_render()
    }

    pub fn toggle_numbers(event: events.UiEvent) {
        self.numbers = event.index == 1
        self.request_render()
    }

    pub fn toggle_values(event: events.UiEvent) {
        self.values = event.index == 1
        self.request_render()
    }

    pub fn toggle_boxes(event: events.UiEvent) {
        self.boxes = event.index == 1
        self.request_render()
    }

    pub fn toggle_rows(event: events.UiEvent) {
        self.rows = event.index == 1
        self.request_render()
    }

    pub fn toggle_systems(event: events.UiEvent) {
        self.systems = event.index == 1
        self.request_render()
    }

    pub fn order() {
        self.status = "Ordered {self.shots} × {self.drink}"
        self.request_render()
    }

    /// What `<FancyButton on_press=...>` runs. The component holds the button;
    /// the screen holds what pressing it means.
    pub fn clear() {
        self.status = "Nothing ordered yet"
        self.request_render()
    }
}

// Every component tag in shelf.bx, checked by beansc rather than by cortado-bx:
// a tag whose type is not a Component is a type error naming the type,
// instead of a blank subtree and a fault at run time. Unused, and an
// unused free function is not an error.
fn _cortado_component_shelf_ShaderCanvas(value: ShaderCanvas) -> Component { return value }
fn _cortado_component_shelf_ShapeCanvas(value: ShapeCanvas) -> Component { return value }
fn _cortado_component_shelf_FancyButton(value: FancyButton) -> Component { return value }

partial class Shelf {
    pub override fn render(b: Builder) {
        b.open("VStack")  // shelf.bx:1
        b.number("spacing", (10) as f64)
        b.number("padding", (16) as f64)
        b.word("align", "stretch")
        b.open("ScrollView")  // shelf.bx:2
        b.number("grow", (1) as f64)
        b.open("VStack")  // shelf.bx:3
        b.number("spacing", (10) as f64)
        b.word("align", "stretch")
        b.open("Label")  // shelf.bx:4
        b.number("font_size", (18) as f64)
        b.text("Every control cortado has")
        b.close()
        b.open("Label")  // shelf.bx:5
        b.text("{self.inventory}")
        b.close()
        b.open("Separator")  // shelf.bx:6
        b.close()
        b.open("Disclosure")  // shelf.bx:9
        b.text("Words")
        b.flag("open", self.words)
        b.on("change", fn(e: UiEvent) { self.toggle_words(e) })
        b.open("VStack")  // shelf.bx:11
        b.number("spacing", (8) as f64)
        b.number("padding", (8) as f64)
        b.word("align", "stretch")
        b.open("HStack")  // shelf.bx:12
        b.number("spacing", (10) as f64)
        b.open("Label")  // shelf.bx:13
        b.number("width", (110) as f64)
        b.text("Name")
        b.close()
        b.open("TextField")  // shelf.bx:14
        b.number("grow", (1) as f64)
        b.on("commit", fn(_e: UiEvent) { self.name = _e.text })
        b.text("{self.name}")
        b.close()
        b.close()
        b.open("HStack")  // shelf.bx:16
        b.number("spacing", (10) as f64)
        b.open("Label")  // shelf.bx:17
        b.number("width", (110) as f64)
        b.text("Passphrase")
        b.close()
        b.open("SecureField")  // shelf.bx:18
        b.number("grow", (1) as f64)
        b.close()
        b.close()
        b.open("HStack")  // shelf.bx:20
        b.number("spacing", (10) as f64)
        b.open("Label")  // shelf.bx:21
        b.number("width", (110) as f64)
        b.text("Search")
        b.close()
        b.open("SearchField")  // shelf.bx:22
        b.number("grow", (1) as f64)
        b.close()
        b.close()
        b.open("TextArea")  // shelf.bx:24
        b.number("height", (56) as f64)
        b.on("commit", fn(_e: UiEvent) { self.note = _e.text })
        b.text("{self.note}")
        b.close()
        b.open("Link")  // shelf.bx:25
        b.text("Read the manual")
        b.close()
        b.close()
        b.close()
        b.open("Disclosure")  // shelf.bx:30
        b.text("Choices")
        b.flag("open", self.choices)
        b.on("change", fn(e: UiEvent) { self.toggle_choices(e) })
        b.open("VStack")  // shelf.bx:32
        b.number("spacing", (8) as f64)
        b.number("padding", (8) as f64)
        b.word("align", "stretch")
        b.open("HStack")  // shelf.bx:33
        b.number("spacing", (10) as f64)
        b.open("Label")  // shelf.bx:34
        b.number("width", (110) as f64)
        b.text("Drink")
        b.close()
        b.open("ComboBox")  // shelf.bx:35
        b.number("grow", (1) as f64)
        b.on("change", fn(e: UiEvent) { self.pick(e.index) })
        b.close()
        b.close()
        b.open("HStack")  // shelf.bx:37
        b.number("spacing", (10) as f64)
        b.open("CheckBox")  // shelf.bx:38
        b.flag("checked", self.rush)
        b.on("change", fn(e: UiEvent) { self.toggle_rush() })
        b.text("Rush it")
        b.close()
        b.open("RadioButton")  // shelf.bx:39
        b.text("Eat in")
        b.close()
        b.open("RadioButton")  // shelf.bx:40
        b.text("Take away")
        b.close()
        b.close()
        if self.has_switch {  // shelf.bx:42
            b.open("HStack")  // shelf.bx:43
            b.number("spacing", (10) as f64)
            b.open("Label")  // shelf.bx:44
            b.number("width", (110) as f64)
            b.text("Keep warm")
            b.close()
            b.open("Switch")  // shelf.bx:45
            b.flag("checked", self.warm)
            b.on("change", fn(e: UiEvent) { self.toggle_warm(e) })
            b.close()
            b.close()
        }
        if !self.has_switch {  // shelf.bx:48
            b.open("Label")  // shelf.bx:49
            b.text("no toggle switch on this platform")
            b.close()
        }
        if self.has_segmented {  // shelf.bx:51
            b.open("Segmented")  // shelf.bx:52
            b.close()
        }
        if !self.has_segmented {  // shelf.bx:54
            b.open("Label")  // shelf.bx:55
            b.text("no segmented control on this platform")
            b.close()
        }
        b.close()
        b.close()
        b.open("Disclosure")  // shelf.bx:61
        b.text("Numbers")
        b.flag("open", self.numbers)
        b.on("change", fn(e: UiEvent) { self.toggle_numbers(e) })
        b.open("VStack")  // shelf.bx:63
        b.number("spacing", (8) as f64)
        b.number("padding", (8) as f64)
        b.word("align", "stretch")
        b.open("HStack")  // shelf.bx:64
        b.number("spacing", (10) as f64)
        b.open("Label")  // shelf.bx:65
        b.number("width", (110) as f64)
        b.text("Shots: {self.shots}")
        b.close()
        b.open("Slider")  // shelf.bx:66
        b.number("grow", (1) as f64)
        b.number("min", (1) as f64)
        b.number("max", (4) as f64)
        b.number("value", (self.shots) as f64)
        b.on("change", fn(e: UiEvent) { self.set_shots(e) })
        b.close()
        b.close()
        b.open("HStack")  // shelf.bx:69
        b.number("spacing", (10) as f64)
        b.open("Label")  // shelf.bx:70
        b.number("width", (110) as f64)
        b.text("Exactly")
        b.close()
        b.open("Stepper")  // shelf.bx:71
        b.number("min", (1) as f64)
        b.number("max", (4) as f64)
        b.number("step", (1) as f64)
        b.number("value", (self.shots) as f64)
        b.on("change", fn(e: UiEvent) { self.set_shots(e) })
        b.close()
        b.close()
        b.open("ProgressBar")  // shelf.bx:74
        b.number("height", (12) as f64)
        b.number("min", (0) as f64)
        b.number("max", (4) as f64)
        b.number("value", (self.shots) as f64)
        b.close()
        if self.has_level {  // shelf.bx:75
            b.open("LevelIndicator")  // shelf.bx:76
            b.number("height", (16) as f64)
            b.number("min", (0) as f64)
            b.number("max", (4) as f64)
            b.number("value", (self.shots) as f64)
            b.close()
        }
        if !self.has_level {  // shelf.bx:78
            b.open("Label")  // shelf.bx:79
            b.text("no level indicator on this platform")
            b.close()
        }
        if self.has_spinner {  // shelf.bx:81
            b.open("Spinner")  // shelf.bx:82
            b.number("height", (20) as f64)
            b.flag("animating", self.busy)
            b.close()
        }
        if !self.has_spinner {  // shelf.bx:84
            b.open("Label")  // shelf.bx:85
            b.text("no spinner on this platform")
            b.close()
        }
        b.close()
        b.close()
        b.open("Disclosure")  // shelf.bx:91
        b.text("A day and a colour")
        b.flag("open", self.values)
        b.on("change", fn(e: UiEvent) { self.toggle_values(e) })
        b.open("VStack")  // shelf.bx:93
        b.number("spacing", (8) as f64)
        b.number("padding", (8) as f64)
        b.word("align", "stretch")
        b.open("HStack")  // shelf.bx:94
        b.number("spacing", (10) as f64)
        b.open("Label")  // shelf.bx:95
        b.number("width", (110) as f64)
        b.text("When")
        b.close()
        b.open("DatePicker")  // shelf.bx:96
        b.number("grow", (1) as f64)
        b.number("day", (self.day) as f64)
        b.on("change", fn(e: UiEvent) { self.set_day(e) })
        b.close()
        b.close()
        if self.has_color {  // shelf.bx:99
            b.open("HStack")  // shelf.bx:100
            b.number("spacing", (10) as f64)
            b.open("Label")  // shelf.bx:101
            b.number("width", (110) as f64)
            b.text("Marker")
            b.close()
            b.open("ColorWell")  // shelf.bx:102
            b.number("width", (60) as f64)
            b.number("height", (24) as f64)
            b.word("color", "#3b82f6")
            b.on("change", fn(e: UiEvent) { self.set_color(e) })
            b.close()
            b.close()
        }
        if !self.has_color {  // shelf.bx:106
            b.open("Label")  // shelf.bx:107
            b.text("no colour well on this platform")
            b.close()
        }
        b.open("Label")  // shelf.bx:109
        b.text("{self.chosen}")
        b.close()
        b.close()
        b.close()
        b.open("Disclosure")  // shelf.bx:114
        b.text("Boxes and pictures")
        b.flag("open", self.boxes)
        b.on("change", fn(e: UiEvent) { self.toggle_boxes(e) })
        b.open("VStack")  // shelf.bx:116
        b.number("spacing", (8) as f64)
        b.number("padding", (8) as f64)
        b.word("align", "stretch")
        if self.has_group {  // shelf.bx:117
            b.open("GroupBox")  // shelf.bx:118
            b.text("Brewing")
            b.open("VStack")  // shelf.bx:119
            b.number("spacing", (6) as f64)
            b.number("padding", (10) as f64)
            b.word("align", "stretch")
            b.open("CheckBox")  // shelf.bx:120
            b.text("Grind fresh")
            b.close()
            b.open("CheckBox")  // shelf.bx:121
            b.text("Filtered water")
            b.close()
            b.close()
            b.close()
        }
        if !self.has_group {  // shelf.bx:125
            b.open("Label")  // shelf.bx:126
            b.text("no group box on this platform")
            b.close()
        }
        b.open("Image")  // shelf.bx:128
        b.number("height", (20) as f64)
        b.close()
        b.open("Canvas")  // shelf.bx:130
        b.number("height", (20) as f64)
        b.close()
        b.child<ShaderCanvas>("c8", fn(_cortado_c: ShaderCanvas) {  // shelf.bx:133
            _cortado_c.effect = "ripple"
            _cortado_c.color = "#4088bf"
            _cortado_c.color_to = "#0d1b2a"
            _cortado_c.detail = 26
        }).number("height", (44) as f64)
        b.child<ShapeCanvas>("c9", fn(_cortado_c: ShapeCanvas) {  // shelf.bx:137
            _cortado_c.figure = "rounded_rect"
            _cortado_c.radius = 10
            _cortado_c.inset = 6
            _cortado_c.fill = "gradient"
            _cortado_c.color = "#4088bf"
            _cortado_c.color_to = "#0d1b2a"
            _cortado_c.stroke = "#8fb7d4"
            _cortado_c.stroke_width = 1
        }).number("height", (44) as f64)
        b.close()
        b.close()
        b.open("Disclosure")  // shelf.bx:146
        b.text("Rows")
        b.flag("open", self.rows)
        b.on("change", fn(e: UiEvent) { self.toggle_rows(e) })
        b.open("VStack")  // shelf.bx:148
        b.number("spacing", (8) as f64)
        b.number("padding", (8) as f64)
        b.word("align", "stretch")
        b.open("Table")  // shelf.bx:149
        b.number("height", (80) as f64)
        b.close()
        b.open("ScrollView")  // shelf.bx:150
        b.number("height", (60) as f64)
        b.open("VStack")  // shelf.bx:151
        b.number("spacing", (4) as f64)
        b.number("padding", (4) as f64)
        b.word("align", "stretch")
        b.open("Label")  // shelf.bx:152
        b.text("More than fits")
        b.close()
        b.open("Label")  // shelf.bx:153
        b.text("so the rest scrolls")
        b.close()
        b.open("Label")  // shelf.bx:154
        b.text("and nothing is clipped away")
        b.close()
        b.close()
        b.close()
        b.close()
        b.close()
        b.open("Disclosure")  // shelf.bx:165
        b.text("Pages, panes and a browser")
        b.flag("open", self.systems)
        b.on("change", fn(e: UiEvent) { self.toggle_systems(e) })
        b.open("VStack")  // shelf.bx:167
        b.number("spacing", (8) as f64)
        b.number("padding", (8) as f64)
        b.word("align", "stretch")
        if self.has_tabs {  // shelf.bx:168
            b.open("TabView")  // shelf.bx:169
            b.number("height", (90) as f64)
            b.open("Container")  // shelf.bx:170
            b.close()
            b.open("Container")  // shelf.bx:171
            b.close()
            b.close()
        }
        if !self.has_tabs {  // shelf.bx:174
            b.open("Label")  // shelf.bx:175
            b.text("no tab view on this platform")
            b.close()
        }
        if self.has_split {  // shelf.bx:177
            b.open("SplitView")  // shelf.bx:184
            b.number("height", (70) as f64)
            b.open("VStack")  // shelf.bx:185
            b.number("padding", (4) as f64)
            b.word("align", "stretch")
            b.open("Label")  // shelf.bx:186
            b.text("this pane")
            b.close()
            b.close()
            b.open("VStack")  // shelf.bx:188
            b.number("padding", (4) as f64)
            b.word("align", "stretch")
            b.open("Label")  // shelf.bx:189
            b.text("and this one")
            b.close()
            b.close()
            b.close()
        }
        if !self.has_split {  // shelf.bx:193
            b.open("Label")  // shelf.bx:194
            b.text("no split view on this platform")
            b.close()
        }
        if self.has_tree {  // shelf.bx:196
            b.open("OutlineView")  // shelf.bx:197
            b.number("height", (90) as f64)
            b.close()
        }
        if !self.has_tree {  // shelf.bx:199
            b.open("Label")  // shelf.bx:200
            b.text("no outline view on this platform")
            b.close()
        }
        if self.has_web {  // shelf.bx:202
            b.open("WebView")  // shelf.bx:203
            b.number("height", (90) as f64)
            b.close()
        }
        if !self.has_web {  // shelf.bx:205
            b.open("Label")  // shelf.bx:206
            b.text("no browser engine on this platform")
            b.close()
        }
        b.close()
        b.close()
        b.open("HStack")  // shelf.bx:215
        b.number("spacing", (10) as f64)
        b.word("justify", "end")
        b.child<FancyButton>("c10", fn(_cortado_c: FancyButton) {  // shelf.bx:216
            _cortado_c.title = "Clear"
            _cortado_c.tint = self.accent
            _cortado_c.enabled = self.shots > 0
            _cortado_c.on_press = fn(e: UiEvent) { self.clear() }
        })
        b.open("Button")  // shelf.bx:218
        b.flag("enabled", self.shots > 0)
        b.word("background", "#2f6f4f")
        b.number("corner_radius", (6) as f64)
        b.number("border_width", (1) as f64)
        b.word("border_color", "#00000040")
        b.on("click", fn(e: UiEvent) { self.order() })
        b.text("Order")
        b.close()
        b.close()
        b.open("Label")  // shelf.bx:223
        b.text("{self.status}")
        b.close()
        b.close()
        b.close()
        b.close()
    }
}
