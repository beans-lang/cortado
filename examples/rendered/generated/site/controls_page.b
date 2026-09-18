// Generated from site/controls_page.bx by cortado. Do not edit.
//
// The <beans> block below is controls_page.bx's, copied through byte for byte; its
// own package line is blanked so every line after it keeps its number. The
// render method under it is the markup, as Builder calls.
// Change controls_page.bx and regenerate:
//
//     cortado generate site/controls_page.bx
package site

import {Builder, Component} from cortado.component
import {UiEvent} from cortado.events


//          

import cortado.component
import {view} from cortado.annotations

@view
pub partial class ControlsPage extends component.Component {
    pub checked: int = 0
    pub small: int = 1
    pub large: int = 0
    pub on: int = 1
    pub intensity: f64 = 40.0
    pub last_slider_event_value: f64 = -1.0
    pub shots: f64 = 2.0
    pub progress: f64 = 35.0
    pub size: string = "Small"
    pub details_open: int = 0
    pub detail_clicks: int = 0
    pub fn init() { super.init() }
    pub fn check(value: int) { self.checked = value; self.request_render() }
    pub fn choose_small(value: int) {
        if value == 1 { self.small = 1; self.large = 0; self.size = "Small"; self.request_render() }
    }
    pub fn choose_large(value: int) {
        if value == 1 { self.small = 0; self.large = 1; self.size = "Large"; self.request_render() }
    }
    pub fn flip(value: int) { self.on = value; self.request_render() }
    pub fn slide(value: int, event_value: f64) {
        self.intensity = value as f64; self.last_slider_event_value = event_value
        self.request_render()
    }
    pub fn step(value: int) { self.shots = value as f64; self.request_render() }
    pub fn set_details(value: int) { self.details_open = value; self.request_render() }
    pub fn note_detail() { self.detail_clicks += 1; self.request_render() }
}

partial class ControlsPage {
    pub override fn render(b: Builder) {
        b.open("VStack")  // controls_page.bx:1
        b.number("padding", (20) as f64)
        b.number("spacing", (12) as f64)
        b.word("align", "stretch")
        b.open("Label")  // controls_page.bx:2
        b.text("Shared controls")
        b.number("font_size", (23) as f64)
        b.close()
        b.open("Label")  // controls_page.bx:3
        b.text("Every control below uses a .bx visual.")
        b.word("text_color", "#555b6b")
        b.close()
        b.open("CheckBox")  // controls_page.bx:4
        b.key("{"check"}")
        b.text("Include milk")
        b.flag("checked", self.checked == 1)
        b.on("change", fn(e: UiEvent) { self.check(e.index) })
        b.close()
        b.open("HStack")  // controls_page.bx:6
        b.number("spacing", (12) as f64)
        b.word("align", "center")
        b.open("RadioButton")  // controls_page.bx:7
        b.key("{"small"}")
        b.text("Small")
        b.flag("checked", self.small == 1)
        b.on("change", fn(e: UiEvent) { self.choose_small(e.index) })
        b.close()
        b.open("RadioButton")  // controls_page.bx:9
        b.key("{"large"}")
        b.text("Large")
        b.flag("checked", self.large == 1)
        b.on("change", fn(e: UiEvent) { self.choose_large(e.index) })
        b.close()
        b.close()
        b.open("HStack")  // controls_page.bx:12
        b.number("spacing", (12) as f64)
        b.word("align", "center")
        b.open("Label")  // controls_page.bx:13
        b.text("Notifications")
        b.number("grow", (1) as f64)
        b.close()
        b.open("Switch")  // controls_page.bx:14
        b.key("{"switch"}")
        b.flag("checked", self.on == 1)
        b.on("change", fn(e: UiEvent) { self.flip(e.index) })
        b.close()
        b.close()
        b.open("Label")  // controls_page.bx:17
        b.text("Intensity {self.intensity}")
        b.close()
        b.open("Slider")  // controls_page.bx:18
        b.key("{"slider"}")
        b.number("min", (0.0) as f64)
        b.number("max", (100.0) as f64)
        b.number("value", (self.intensity) as f64)
        b.number("step", (5.0) as f64)
        b.on("change", fn(e: UiEvent) { self.slide(e.index, e.position.x) })
        b.close()
        b.open("HStack")  // controls_page.bx:20
        b.number("spacing", (12) as f64)
        b.word("align", "center")
        b.open("Label")  // controls_page.bx:21
        b.text("Shots")
        b.number("grow", (1) as f64)
        b.close()
        b.open("Stepper")  // controls_page.bx:22
        b.key("{"stepper"}")
        b.number("min", (0.0) as f64)
        b.number("max", (10.0) as f64)
        b.number("value", (self.shots) as f64)
        b.number("step", (1.0) as f64)
        b.on("change", fn(e: UiEvent) { self.step(e.index) })
        b.close()
        b.close()
        b.open("Label")  // controls_page.bx:25
        b.text("Progress {self.progress}%")
        b.close()
        b.open("ProgressBar")  // controls_page.bx:26
        b.key("{"progress"}")
        b.number("min", (0.0) as f64)
        b.number("max", (100.0) as f64)
        b.number("value", (self.progress) as f64)
        b.close()
        b.open("Label")  // controls_page.bx:27
        b.text("Level")
        b.close()
        b.open("LevelIndicator")  // controls_page.bx:28
        b.key("{"level"}")
        b.number("min", (0.0) as f64)
        b.number("max", (100.0) as f64)
        b.number("value", (self.intensity) as f64)
        b.close()
        b.open("Separator")  // controls_page.bx:29
        b.number("height", (1) as f64)
        b.close()
        b.open("GroupBox")  // controls_page.bx:30
        b.text("Order options")
        b.number("height", (72) as f64)
        b.open("Label")  // controls_page.bx:31
        b.text("Beans, milk, and cup size")
        b.close()
        b.close()
        b.open("Disclosure")  // controls_page.bx:33
        b.key("{"details"}")
        b.text("Order details")
        b.flag("open", self.details_open == 1)
        b.number("height", (72) as f64)
        b.on("change", fn(e: UiEvent) { self.set_details(e.index) })
        b.open("Button")  // controls_page.bx:35
        b.key("{"detail_action"}")
        b.text("Roasted today")
        b.on("click", fn(e: UiEvent) { self.note_detail() })
        b.close()
        b.close()
        b.open("Label")  // controls_page.bx:38
        b.text("Milk {self.checked}, size {self.size}, notifications {self.on}, shots {self.shots}")
        b.word("text_color", "#555b6b")
        b.close()
        b.close()
    }
}
