package main

import cortado_skia
import cortado.geometry
import cortado.widgets
import cortado.events
import cortado.host
import cortado.render
import {ControlsPage} from rendered_demo.generated.site
import std.io
import std.math

fn require(value: bool, message: string) { if !value { panic(message) } }

fn find(root: widgets.Widget, kind: widgets.WidgetKind, text: string = "") -> Option<widgets.Widget> {
    if root.kind() == kind && (text == "" || root.display_text().expect("control text") == text) { return some(root) }
    for child: widgets.Widget in root.children() {
        match find(child, kind, text) { some(found) => { return some(found) } none => {} }
    }
    return none
}

fn click(scene: cortado_skia.Scene, widget: widgets.Widget, fraction: f64 = 0.5) -> Result<bool> {
    let frame: geometry.Rect = scene.global_frame(widget.render_object()?)?
    let point: geometry.Point = geometry.Point.at(frame.x + frame.width * fraction, frame.y + frame.height / 2.0)
    scene.pointer(events.EventKind.pointer_down, point)?
    return scene.pointer(events.EventKind.pointer_up, point)
}

fn has_semantics(scene: cortado_skia.Scene, handle: u64) -> bool {
    for node: render.SemanticsNode in scene.semantics() { if node.id() == handle { return true } }
    return false
}

fn verify() -> Result<bool> {
    let view: ControlsPage = new ControlsPage()
    let scene: cortado_skia.Scene = new cortado_skia.Scene(geometry.Size.of(600.0, 680.0))
    scene.show(view)?
    let check: widgets.CheckBox = (find(scene.root(), widgets.WidgetKind.check_box).expect("check box") as? widgets.CheckBox).expect("check box type")
    let small: widgets.RadioButton = (find(scene.root(), widgets.WidgetKind.radio_button, "Small").expect("small radio") as? widgets.RadioButton).expect("radio type")
    let large: widgets.RadioButton = (find(scene.root(), widgets.WidgetKind.radio_button, "Large").expect("large radio") as? widgets.RadioButton).expect("radio type")
    let toggle: widgets.Switch = (find(scene.root(), widgets.WidgetKind.switch).expect("switch") as? widgets.Switch).expect("switch type")
    let slider: widgets.Slider = (find(scene.root(), widgets.WidgetKind.slider).expect("slider") as? widgets.Slider).expect("slider type")
    let stepper: widgets.Stepper = (find(scene.root(), widgets.WidgetKind.stepper).expect("stepper") as? widgets.Stepper).expect("stepper type")
    let progress: widgets.ProgressBar = (find(scene.root(), widgets.WidgetKind.progress_bar).expect("progress") as? widgets.ProgressBar).expect("progress type")
    let level: widgets.LevelIndicator = (find(scene.root(), widgets.WidgetKind.level_indicator).expect("level") as? widgets.LevelIndicator).expect("level type")
    let separator: widgets.Separator = (find(scene.root(), widgets.WidgetKind.separator).expect("separator") as? widgets.Separator).expect("separator type")
    let group: widgets.GroupBox = (find(scene.root(), widgets.WidgetKind.group_box).expect("group box") as? widgets.GroupBox).expect("group type")
    let disclosure: widgets.Disclosure = (find(scene.root(), widgets.WidgetKind.disclosure).expect("disclosure") as? widgets.Disclosure).expect("disclosure type")
    let detail: widgets.Button = (find(disclosure, widgets.WidgetKind.button, "Roasted today").expect("retained detail") as? widgets.Button).expect("detail type")
    let detail_id: u64 = detail.handle().raw

    require(check.a11y_role()? == "checkbox" && check.state()? == widgets.CheckState.off, "check box did not mount")
    click(scene, check)?
    require(view.checked == 1 && check.state()? == widgets.CheckState.on, "check box click did not update Beans")
    check.set_state(widgets.CheckState.mixed)?
    require(check.state()? == widgets.CheckState.mixed, "mixed check state was lost")
    check.activate()?
    scene.refresh()?
    require(view.checked == 0 && check.state()? == widgets.CheckState.off, "public activation did not toggle check box")
    click(scene, check)?
    require(view.checked == 1 && check.state()? == widgets.CheckState.on, "check box did not turn back on")
    require(toggle.a11y_role()? == "switch", "switch role was lost")
    click(scene, toggle)?
    require(view.on == 0 && !toggle.is_on()?, "switch click did not update Beans")

    click(scene, large)?
    require(large.is_chosen()? && !small.is_chosen()? && view.size == "Large", "radio siblings were not exclusive")
    require(check.state()? == widgets.CheckState.on && !toggle.is_on()?, "radio choice cleared unrelated toggle")
    click(scene, small)?
    require(small.is_chosen()? && !large.is_chosen()? && view.size == "Small", "radio selection did not switch back")
    require(!large.set_value_as_user(0, 0.0)?, "already unselected radio reported a change")
    require(small.is_chosen()?, "deselecting an unselected radio cleared its sibling")

    click(scene, slider, 0.75)?
    require(view.intensity >= 70.0 && view.intensity <= 80.0, "slider drag did not update component")
    require(slider.value()? == view.intensity, "slider value and binding diverged")
    slider.set_value_as_user(0, 77.0)?
    scene.refresh()?
    require(slider.value()? == 75.0 && view.intensity == 75.0 && view.last_slider_event_value == 75.0,
            "slider snap event reported unsnapped value")
    match slider.set_value_as_user(0, math.infinity()) { ok(_) => { panic("infinite slider value was accepted") } err(_) => {} }
    match slider.set_value_as_user(0, math.infinity() - math.infinity()) { ok(_) => { panic("NaN slider value was accepted") } err(_) => {} }
    let old_shots: f64 = view.shots
    let stepper_frame: geometry.Rect = scene.global_frame(stepper.render_object()?)?
    scene.pointer(events.EventKind.pointer_up, geometry.Point.at(stepper_frame.x + stepper_frame.width * 0.9,
                                                                   stepper_frame.y + stepper_frame.height / 2.0))?
    require(view.shots == old_shots, "stepper changed on release without press")
    click(scene, stepper, 0.9)?
    require(view.shots == old_shots + 1.0 && stepper.value()? == view.shots, "stepper click did not increment")
    scene.pointer(events.EventKind.pointer_down, geometry.Point.at(stepper_frame.x + stepper_frame.width * 0.9,
                                                                     stepper_frame.y + stepper_frame.height / 2.0))?
    scene.pointer(events.EventKind.pointer_up, geometry.Point.at(stepper_frame.x + stepper_frame.width + 20.0,
                                                                   stepper_frame.y + stepper_frame.height / 2.0))?
    require(view.shots == old_shots + 1.0, "stepper changed after release outside")
    match stepper.set_step(0.0) { ok(_) => { panic("zero step was accepted") } err(_) => {} }

    progress.set_value(70.0)?
    require(progress.value()? == 70.0, "progress value was lost")
    progress.set_indeterminate(true)?
    require(progress.is_indeterminate()?, "indeterminate mode was lost")
    match progress.set_property_real(host.P_STEP, 1.0) { ok(_) => { panic("progress accepted unsupported step") } err(_) => {} }
    level.set_level(65.0)?
    require(level.level()? == 65.0 && level.a11y_role()? == "meter", "level indicator was lost")
    require(separator.a11y_role()? == "separator", "separator role was lost")
    require(group.title()? == "Order options" && group.content_inset()?.top >= 20.0, "group box chrome or inset missing")
    require(!disclosure.is_open()? && !has_semantics(scene, detail_id), "closed disclosure exposed child semantics")
    match detail.focus() { ok(_) => { panic("closed disclosure child took focus") } err(_) => {} }
    disclosure.set_value_as_user(1, 1.0)?
    scene.refresh()?
    require(disclosure.is_open()? && view.details_open == 1, "disclosure did not open")
    require(has_semantics(scene, detail_id) && detail.handle().raw == detail_id, "opening replaced or hid retained child")
    detail.focus()?
    click(scene, detail)?
    require(view.detail_clicks == 1, "open disclosure child did not receive click")
    disclosure.set_value_as_user(0, 0.0)?
    scene.refresh()?
    require(!disclosure.is_open()? && !has_semantics(scene, detail_id), "closing left child exposed")
    require(!detail.focused(), "closed disclosure child kept focus")
    scene.refresh()?
    require(!scene.refresh()?, "controls kept repainting when idle")
    scene.renderer().write_png("build/rendered-controls.png")?
    scene.close()
    require(!check.is_alive(), "scene close left live controls")
    io.println("ok shared toggles, ranges, templates, events, and teardown")
    return ok(true)
}

fn main() { match verify() { ok(_) => {} err(problem) => { panic(problem.msg) } } }
