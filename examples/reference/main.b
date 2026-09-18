package main

import cortado_skia
import cortado.geometry
import cortado.render
import cortado.widgets
import cortado.events
import cortado.host
import std.io
import std.fs
import std.os

/// Paints cortado controls onto the same boards the AppKit reference used, so
/// the two sets of PNGs can be subtracted pixel for pixel.
///
/// Every board, pad, frame, appearance and scale is read from the plan the
/// capture wrote. Nothing here invents a size, and a control this build cannot
/// make is reported rather than drawn as something else.

class Shot {
    pub control: string = ""
    pub size: string = ""
    pub state: string = ""
    pub appearance: string = ""
    pub scale: f64 = 1.0
    pub pad: f64 = 12.0
    pub width: f64 = 0.0
    pub height: f64 = 0.0
    pub board_width: f64 = 0.0
    pub board_height: f64 = 0.0
    pub file: string = ""
    pub fn init() {}
}

fn size_code(name: string) -> int {
    if name == "mini" { return 0 }
    if name == "small" { return 1 }
    if name == "large" { return 3 }
    return 2
}

fn is_checked(state: string) -> bool {
    return state == "checked" || state == "pressedChecked" ||
           state == "disabledChecked" || state == "inactiveChecked"
}

/// Builds the one control this shot is about, already carrying its value, and
/// places it on `root`. It returns whether there is a shared control for the
/// shot at all; the caller reads the control back off the container.
fn build(shot: Shot, context: render.UiContext, root: widgets.Container) -> Result<bool> {
    let on: bool = is_checked(shot.state)
    let held: Option<render.UiContext> = some(context)
    if shot.control == "push_button" || shot.control == "default_button" {
        let button: widgets.Button = new widgets.Button(held)
        button.set_title(if shot.control == "default_button" { "Default" } else { "Button" })?
        if shot.control == "default_button" { button.set_prominent(true)? }
        return place(button, shot, root)
    }
    if shot.control == "check_box" || shot.control == "mixed_check_box" {
        let box: widgets.CheckBox = new widgets.CheckBox(held)
        box.set_title(if shot.control == "check_box" { "Check" } else { "Mixed" })?
        box.set_state(if shot.control == "mixed_check_box" { widgets.CheckState.mixed }
                            else if on { widgets.CheckState.on } else { widgets.CheckState.off })?
        return place(box, shot, root)
    }
    if shot.control == "radio_button" {
        let radio: widgets.RadioButton = new widgets.RadioButton(held)
        radio.set_title("Radio")?
        radio.set_chosen(on)?
        return place(radio, shot, root)
    }
    if shot.control == "switch_control" {
        let toggle: widgets.Switch = new widgets.Switch(held)
        toggle.set_on(on)?
        // AppKit keeps one 54 by 24 frame and paints a switch of its own size
        // inside it. Cortado's switch is as big as it paints, so it is centred
        // on the same board and the two still overlay.
        let wanted: geometry.Size = toggle.render_object()?.measure(geometry.Size.of(shot.width, shot.height))?
        toggle.set_frame(geometry.Rect.of(shot.pad + (shot.width - wanted.width) / 2.0,
                                          shot.pad + (shot.height - wanted.height) / 2.0,
                                          wanted.width, wanted.height))?
        if shot.state == "disabled" || shot.state == "disabledChecked" { toggle.set_enabled(false)? }
        root.add(toggle)?
        return ok(true)
    }
    if shot.control == "popup_button" {
        let combo: widgets.ComboBox = new widgets.ComboBox(held)
        combo.set_items(["Choose", "Other"])?
        return place(combo, shot, root)
    }
    if shot.control == "segmented" {
        let segmented: widgets.Segmented = new widgets.Segmented(held)
        segmented.set_items(["One", "Two", "Three"])?
        segmented.select(if on { 2 } else { 1 })?
        return place(segmented, shot, root)
    }
    if shot.control == "text_field" || shot.control == "placeholder_field" {
        let field: widgets.TextField = new widgets.TextField(held)
        field.set_value(if shot.control == "text_field" { "Text" } else { "" })?
        return place(field, shot, root)
    }
    if shot.control == "secure_field" {
        let field: widgets.SecureField = new widgets.SecureField(held)
        field.set_value("secret")?
        return place(field, shot, root)
    }
    if shot.control == "search_field" {
        let field: widgets.SearchField = new widgets.SearchField(held)
        field.set_value(if on { "coffee" } else { "" })?
        return place(field, shot, root)
    }
    if shot.control == "stepper" {
        let stepper: widgets.Stepper = new widgets.Stepper(held)
        stepper.set_range(0.0, 10.0)?; stepper.set_step(1.0)?; stepper.set_value(2.0)?
        return place(stepper, shot, root)
    }
    if shot.control == "slider" {
        let slider: widgets.Slider = new widgets.Slider(held)
        slider.set_range(0.0, 1.0)?; slider.set_value(0.45)?
        return place(slider, shot, root)
    }
    if shot.control == "progress_bar" {
        let bar: widgets.ProgressBar = new widgets.ProgressBar(held)
        bar.set_range(0.0, 100.0)?; bar.set_value(45.0)?
        return place(bar, shot, root)
    }
    if shot.control == "level_indicator" {
        let level: widgets.LevelIndicator = new widgets.LevelIndicator(held)
        level.set_range(0.0, 10.0)?; level.set_level(6.0)?
        return place(level, shot, root)
    }
    return ok(false)
}

/// Frames a control the way the reference board did and hands it to the scene.
fn place(widget: widgets.Widget, shot: Shot, root: widgets.Container) -> Result<bool> {
    widget.set_frame(geometry.Rect.of(shot.pad, shot.pad, shot.width, shot.height))?
    if shot.state == "disabled" || shot.state == "disabledChecked" { widget.set_enabled(false)? }
    root.add(widget)?
    return ok(true)
}

/// Draws one shot onto a scene that is reused for the whole plan.
///
/// One scene, not one per shot: a fresh renderer per board would rebuild the
/// Skia engine a thousand times, and the point of the harness is the pixels.
fn render_one(scene: cortado_skia.Scene, shot: Shot, out_dir: string) -> Result<bool> {
    let context: render.UiContext = scene.context()
    let root: widgets.Container = scene.root()
    for root.count() > 0 { root.remove(root.count() - 1)? }
    let theme: render.Theme = context.theme()
    theme.set_dark(shot.appearance == "dark")
    theme.set_window_active(shot.state != "inactive" && shot.state != "inactiveChecked")
    theme.set_control_size(size_code(shot.size))?
    scene.resize(geometry.Size.of(shot.board_width, shot.board_height), shot.scale)?
    if !build(shot, context, root)? { return ok(false) }
    scene.refresh()?
    match root.child_at(0) {
        none => { return err("the control vanished from the board", "missing_control") }
        some(widget) => {
            // A control AppKit never focuses is drawn unfocused rather than
            // refused: the comparison still has to cover the row.
            if shot.state == "focused" {
                match context.focus(widget.handle().raw) { ok(done) => {} err(problem) => {} }
            }
            if shot.state == "pressed" || shot.state == "pressedChecked" {
                // A real pointer press, so the template sees the state the same
                // way it does in a running window. Focus is dropped again: the
                // native pressed shot was highlighted, not made first responder,
                // so a focus ring here would be compared against nothing.
                context.pointer(root.render_object()?, events.EventKind.pointer_down,
                    geometry.Point.at(shot.pad + shot.width / 2.0, shot.pad + shot.height / 2.0),
                    host.BTN_LEFT)?
                match context.focus(0) { ok(done) => {} err(problem) => {} }
            }
        }
    }
    scene.refresh()?
    // A still is of a settled control. The native shot was taken after AppKit
    // finished; a cortado shot taken mid-transition would be compared against
    // an end state and read as a colour bug.
    for step: int in 0..64 {
        if !scene.has_active_animations() { break }
        scene.advance(0.05)?
    }
    scene.refresh()?
    scene.renderer().write_png("{out_dir}/{shot.file}")?
    return ok(true)
}

fn parse(line: string) -> Option<Shot> {
    let parts: List<string> = line.split("\t")
    if parts.len() < 11 { return none }
    var shot: Shot = new Shot()
    shot.control = parts[0]; shot.size = parts[1]; shot.state = parts[2]
    shot.appearance = parts[3]
    match parts[4].to_float() { ok(value) => { shot.scale = value } err(problem) => { return none } }
    match parts[5].to_float() { ok(value) => { shot.pad = value } err(problem) => { return none } }
    match parts[6].to_float() { ok(value) => { shot.width = value } err(problem) => { return none } }
    match parts[7].to_float() { ok(value) => { shot.height = value } err(problem) => { return none } }
    match parts[8].to_float() { ok(value) => { shot.board_width = value } err(problem) => { return none } }
    match parts[9].to_float() { ok(value) => { shot.board_height = value } err(problem) => { return none } }
    shot.file = parts[10]
    return some(shot)
}

fn run(plan: string, out_dir: string) -> Result<bool> {
    let text: string = fs.read(plan)?
    let lines: List<string> = text.split("\n")
    var widest: f64 = 1.0
    var tallest: f64 = 1.0
    var plan_shots: List<Shot> = []
    for line: string in lines {
        if line.trim() == "" { continue }
        match parse(line) {
            none => { return err("bad plan line: {line}", "bad_plan") }
            some(shot) => {
                if shot.board_width > widest { widest = shot.board_width }
                if shot.board_height > tallest { tallest = shot.board_height }
                plan_shots.push(shot)
            }
        }
    }
    let scene: cortado_skia.Scene = new cortado_skia.Scene(geometry.Size.of(widest, tallest))
    var drawn: int = 0
    var skipped: List<string> = []
    for shot: Shot in plan_shots {
        match render_one(scene, shot, out_dir) {
            ok(done) => { if done { drawn += 1 } else { skipped.push(shot.file) } }
            err(problem) => { scene.close(); return err("{shot.file}: {problem.msg}", problem.kind) }
        }
    }
    scene.close()
    io.println("drew {drawn} shot(s)")
    if skipped.len() > 0 {
        io.println("no shared control for {skipped.len()} shot(s); the first is {skipped[0]}")
    }
    return ok(true)
}

fn main() {
    let args: List<string> = os.args()
    if args.len() < 2 {
        io.println("usage: reference <plan.tsv> <out-dir>")
        os.exit(2)
    }
    match run(args[0], args[1]) {
        ok(done) => {}
        err(problem) => { io.println("reference failed: {problem.msg}"); os.exit(1) }
    }
}
