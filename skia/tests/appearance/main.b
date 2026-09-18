// What the macOS look is made of, held to the numbers the capture measured.
//
// Every value here came from `tools/reference/capture.sh` (still geometry) or
// `tools/reference/motion.sh` (recorded clicks). The cases are the three kinds
// of defect that keep coming back: a shape that drifts off centre when the
// device grid moves under it, a control size that changes some numbers and not
// others, and an animation that jumps when it is interrupted.
package main

import cortado_skia
import cortado.events
import cortado.geometry
import cortado.host
import cortado.paint
import cortado.render
import cortado.visual
import cortado.widgets
import std.io

fn require(value: bool, message: string) { if !value { panic(message) } }
fn close_to(a: f64, b: f64, slack: f64) -> bool {
    let gap: f64 = if a > b { a - b } else { b - a }
    return gap <= slack
}

/// Every drawing in a control's template, in painting order.
fn drawings(node: render.RenderObject, out: List<render.RenderObject>) {
    match node as? render.VisualRender { some(_) => { out.push(node) } none => {} }
    for index: int in 0..node.child_count() {
        match node.child_at(index) { some(child) => { drawings(child, out) } none => {} }
    }
}
fn control_drawings(widget: widgets.Widget) -> Result<List<render.RenderObject>> {
    var found: List<render.RenderObject> = []
    match widget.render_object()?.visual() {
        some(root) => { drawings(root, found) }
        none => { return err("control has no template visual", "missing_template") }
    }
    return ok(move found)
}
/// A drawing's painted box in its parent's coordinates, offsets included.
fn painted(node: render.RenderObject) -> geometry.Rect {
    let box: geometry.Rect = node.frame()
    var dx: f64 = 0.0
    var dy: f64 = 0.0
    match node.real(visual.OFFSET_X) { ok(value) => { dx = value } err(_) => {} }
    match node.real(visual.OFFSET_Y) { ok(value) => { dy = value } err(_) => {} }
    return geometry.Rect.of(box.x + dx, box.y + dy, box.width, box.height)
}

fn sizes() -> List<int> { return [0, 1, 2, 3] }

// --------------------------------------------------- 1. the radio button's dot
fn radio_is_concentric(scene: cortado_skia.Scene) -> Result<bool> {
    let context: render.UiContext = scene.context()
    let theme: render.Theme = context.theme()
    for scale: f64 in [1.0, 1.25, 1.5, 2.0] {
        for size: int in sizes() {
            theme.set_control_size(size)?
            let root: widgets.Container = scene.root()
            for root.count() > 0 { root.remove(root.count() - 1)? }
            let radio: widgets.RadioButton = new widgets.RadioButton(some(context))
            radio.set_title("Radio")?
            radio.set_chosen(true)?
            // An odd origin is the case that used to break: two edges of the
            // dot round apart and the dot lands off centre inside its circle.
            radio.set_frame(geometry.Rect.of(7.5, 5.5, 90.0, theme.toggle_size()))?
            root.add(radio)?
            scene.resize(geometry.Size.of(140.0, 40.0), scale)?
            scene.refresh()?
            let marks: List<render.RenderObject> = control_drawings(radio)?
            require(marks.len() == 1, "a selected radio button draws one dot, not {marks.len()}")
            let dot: geometry.Rect = painted(marks[0])
            // The dot fills the circle's own box and is scaled about its centre,
            // so the two boxes are the same box however the grid falls.
            require(close_to(dot.width, dot.height, 0.001), "the dot is not round at scale {scale}")
            require(close_to(dot.width, theme.toggle_size(), 0.001),
                "the dot's box is {dot.width}, not the circle's {theme.toggle_size()} at scale {scale}")
            require(close_to(dot.x, 0.0, 0.001) && close_to(dot.y, 0.0, 0.001),
                "the dot's box is offset from the circle at scale {scale}")
        }
    }
    io.println("ok radio: one dot, concentric with its circle at 1x, 1.25x, 1.5x and 2x")
    return ok(true)
}

// ------------------------------------------- 2. what a control size has to move
fn sizes_move_everything(scene: cortado_skia.Scene) -> Result<bool> {
    let context: render.UiContext = scene.context()
    let theme: render.Theme = context.theme()
    let heights: List<f64> = [16.0, 20.0, 24.0, 28.0]
    let fonts: List<f64> = [9.0, 11.0, 13.0, 13.0]
    let fields: List<f64> = [19.0, 22.0, 24.0, 24.0]
    let baselines: List<f64> = [13.0, 15.0, 17.0, 17.0]
    let dots: List<f64> = [4.0, 5.0, 5.0, 5.0]
    let switches: List<f64> = [36.0, 44.0, 54.0, 64.0]
    for size: int in sizes() {
        theme.set_control_size(size)?
        require(theme.control_height() == heights[size], "control height at size {size}")
        require(theme.font_size() == fonts[size], "font size at size {size}")
        require(theme.field_height() == fields[size], "field height at size {size}")
        require(theme.field_baseline() == baselines[size], "field baseline at size {size}")
        require(theme.radio_dot() == dots[size], "radio dot at size {size}")
        require(theme.switch_width() == switches[size], "switch width at size {size}")
        // A switch is as big as it paints. AppKit keeps one 54 by 24 frame and
        // paints inside it; a frame that small would clamp a large switch's
        // own track, so cortado's frame is the drawing.
        require(theme.switch_travel() ==
                theme.switch_width() - theme.switch_knob_inset() * 2.0 - theme.switch_knob_width(),
            "the knob's travel does not fit its own track at size {size}")

        let root: widgets.Container = scene.root()
        for root.count() > 0 { root.remove(root.count() - 1)? }
        let button: widgets.Button = new widgets.Button(some(context))
        button.set_title("Button")?
        root.add(button)?
        scene.refresh()?
        let measured: geometry.Size = button.render_object()?.measure(geometry.Size.of(400.0, 400.0))?
        require(measured.height == heights[size], "a button measured {measured.height} at size {size}")
        // A mounted template has to have taken the new numbers, not just the theme.
        let mounted: render.RenderObject = button.render_object()?.visual().expect("button template")
        let bezel: render.RenderObject = mounted.child_at(0).expect("button bezel")
        require(close_to(bezel.real(cortado_host_corner()).or(-1.0), theme.control_radius(), 0.001),
            "the button's template kept corner radius {bezel.real(cortado_host_corner()).or(-1.0)} at size {size}, not {theme.control_radius()}")
    }
    theme.set_control_size(2)?
    io.println("ok control sizes: height, font, field, baseline, dot and switch all move together")
    return ok(true)
}
fn cortado_host_corner() -> int { return 22 }

// ---------------------------------------------- 3. the field's text baseline
fn field_sits_on_its_baseline(scene: cortado_skia.Scene) -> Result<bool> {
    let context: render.UiContext = scene.context()
    let theme: render.Theme = context.theme()
    for size: int in sizes() {
        theme.set_control_size(size)?
        let root: widgets.Container = scene.root()
        for root.count() > 0 { root.remove(root.count() - 1)? }
        let field: widgets.TextField = new widgets.TextField(some(context))
        field.set_value("Text")?
        field.set_frame(geometry.Rect.of(10.0, 10.0, 160.0, theme.field_height()))?
        root.add(field)?
        scene.resize(geometry.Size.of(200.0, 60.0), 2.0)?
        scene.refresh()?
        match field.render_object()? as? render.TextFieldRender {
            none => { return err("a text field is not a TextFieldRender", "wrong_kind") }
            some(text) => {
                let caret: geometry.Rect = text.caret_rect()?
                let run: paint.Paragraph = scene.renderer().styled_paragraph("Text",
                    text.text_style(), -1.0, 0x000000ff)?
                let ascent: f64 = run.metrics().baseline
                // Where the paragraph was placed: the caret the field reports,
                // less where that caret sits inside the run itself.
                let placed: f64 = caret.y - run.caret(4).y
                require(close_to(placed, theme.field_baseline() - ascent, 0.001),
                    "the run was placed at {placed} but the baseline wants {theme.field_baseline() - ascent} at size {size}")
                // The caret sits after "Text", so its distance from the run is
                // the same inset the text was drawn at.
                require(close_to(caret.x - run.size().width, theme.field_padding(), 0.5),
                    "the text starts {caret.x - run.size().width} in, not {theme.field_padding()}")
                require(theme.field_padding() == 6.0, "a field's text inset is 6 at every control size")
            }
        }
    }
    theme.set_control_size(2)?
    io.println("ok text field: caret, text and inset share one content box on the native baseline")
    return ok(true)
}

// ------------------------------------------------ 4. the switch's own movement
fn knob_of(toggle: widgets.Switch) -> Result<f64> {
    let marks: List<render.RenderObject> = control_drawings(toggle)?
    require(marks.len() == 2, "a switch draws a track and a knob, not {marks.len()} things")
    return marks[1].real(visual.OFFSET_X)
}

fn switch_motion(scene: cortado_skia.Scene) -> Result<bool> {
    let context: render.UiContext = scene.context()
    let theme: render.Theme = context.theme()
    theme.set_control_size(2)?
    theme.set_reduced_motion(false)
    let root: widgets.Container = scene.root()
    for root.count() > 0 { root.remove(root.count() - 1)? }
    let toggle: widgets.Switch = new widgets.Switch(some(context))
    toggle.set_frame(geometry.Rect.of(10.0, 10.0, theme.switch_width(), theme.switch_height()))?
    root.add(toggle)?
    scene.resize(geometry.Size.of(120.0, 60.0), 2.0)?
    scene.refresh()?
    let travel: f64 = theme.switch_travel()
    // The knob's own box holds the inset, so its offset is the travel alone.
    let centre: f64 = 0.0
    require(close_to(knob_of(toggle)?, centre, 0.001),
        "an off switch put its knob at {knob_of(toggle)?}, not {centre}")
    require(!scene.has_active_animations(), "a switch that was never touched is animating")

    toggle.set_on(true)?
    scene.refresh()?
    require(scene.has_active_animations(), "turning a switch on scheduled no frames")
    scene.advance(theme.motion_switch() / 2.0)?
    let midway: f64 = knob_of(toggle)?
    require(midway > centre + 0.5 && midway < centre + travel - 0.5,
        "the knob jumped to {midway} instead of travelling")

    // Reversed in flight: the knob has to leave from where it is showing.
    toggle.set_on(false)?
    scene.refresh()?
    scene.advance(0.001)?
    let after: f64 = knob_of(toggle)?
    require(after < midway + 0.5 && after > centre,
        "reversing restarted the knob at {after} instead of continuing from {midway}")
    scene.advance(theme.motion_switch() * 2.0)?
    require(close_to(knob_of(toggle)?, centre, 0.001), "the knob did not arrive: {knob_of(toggle)?}")
    require(!scene.has_active_animations(), "a finished switch is still asking for frames")

    // Reduced motion: the same change, no frames at all.
    theme.set_reduced_motion(true)
    scene.refresh()?
    toggle.set_on(true)?
    scene.refresh()?
    require(!scene.has_active_animations(), "reduced motion still scheduled an animation")
    require(close_to(knob_of(toggle)?, centre + travel, 0.001),
        "reduced motion left the knob part way at {knob_of(toggle)?}")
    theme.set_reduced_motion(false)
    io.println("ok switch: slides, reverses from where it is, stops asking for frames, obeys reduced motion")
    return ok(true)
}

/// The same slide, driven the way a person drives it. A press writes a zero
/// duration, so a click that carried its offset before its transition took the
/// press's duration and teleported — the animation only worked from code.
fn switch_press_motion(scene: cortado_skia.Scene) -> Result<bool> {
    let context: render.UiContext = scene.context()
    let theme: render.Theme = context.theme()
    theme.set_control_size(2)?
    theme.set_reduced_motion(false)
    let root: widgets.Container = scene.root()
    for root.count() > 0 { root.remove(root.count() - 1)? }
    let toggle: widgets.Switch = new widgets.Switch(some(context))
    toggle.set_frame(geometry.Rect.of(10.0, 10.0, theme.switch_width(), theme.switch_height()))?
    root.add(toggle)?
    scene.resize(geometry.Size.of(120.0, 60.0), 2.0)?
    scene.refresh()?
    let travel: f64 = theme.switch_travel()
    let middle: geometry.Point = geometry.Point.at(10.0 + theme.switch_width() / 2.0,
                                                   10.0 + theme.switch_height() / 2.0)

    scene.pointer(events.EventKind.pointer_down, middle)?
    require(close_to(knob_of(toggle)?, 0.0, 0.001), "pressing a switch moved its knob")
    require(!scene.has_active_animations(), "a press animates; it is instant")
    scene.pointer(events.EventKind.pointer_up, middle)?
    require(toggle.is_on()?, "the click did not turn the switch on")
    require(scene.has_active_animations(), "a clicked switch scheduled no frames")
    require(close_to(knob_of(toggle)?, 0.0, 0.001), "the knob left before the first frame")
    scene.advance(theme.motion_switch() / 2.0)?
    let midway: f64 = knob_of(toggle)?
    require(midway > 0.5 && midway < travel - 0.5, "a clicked knob jumped to {midway}")
    scene.advance(theme.motion_switch() * 2.0)?
    require(close_to(knob_of(toggle)?, travel, 0.001), "the knob did not arrive: {knob_of(toggle)?}")
    require(!scene.has_active_animations(), "a finished switch is still asking for frames")

    // And back, so the off direction is not taken on trust.
    scene.pointer(events.EventKind.pointer_down, middle)?
    scene.pointer(events.EventKind.pointer_up, middle)?
    require(!toggle.is_on()?, "the second click did not turn the switch off")
    scene.advance(theme.motion_switch() / 2.0)?
    let back: f64 = knob_of(toggle)?
    require(back > 0.5 && back < travel - 0.5, "the knob jumped back to {back}")
    scene.advance(theme.motion_switch() * 2.0)?
    require(close_to(knob_of(toggle)?, 0.0, 0.001), "the knob did not return: {knob_of(toggle)?}")
    io.println("ok switch press: a real click slides the knob, a press itself is instant")
    return ok(true)
}

// ------------------------------------------------- 5. the popup's own menu
fn menu_matches_appkit(scene: cortado_skia.Scene) -> Result<bool> {
    let context: render.UiContext = scene.context()
    let theme: render.Theme = context.theme()
    theme.set_control_size(2)?
    let root: widgets.Container = scene.root()
    for root.count() > 0 { root.remove(root.count() - 1)? }
    let combo: widgets.ComboBox = new widgets.ComboBox(some(context))
    combo.set_items(["Espresso", "Latte", "Cortado"])?
    combo.select(1)?
    root.add(combo)?
    scene.resize(geometry.Size.of(400.0, 200.0), 2.0)?
    scene.refresh()?
    match combo.render_object()? as? render.ComboBoxRender {
        none => { return err("a combo box is not a ComboBoxRender", "wrong_kind") }
        some(choice) => {
            let bounds: geometry.Rect = choice.popup_bounds()
            var widest: f64 = 0.0
            for item: string in ["Espresso", "Latte", "Cortado"] {
                let run: f64 = scene.renderer().styled_paragraph(item,
                    choice.text_style(), -1.0, 0x000000ff)?.size().width
                if run > widest { widest = run }
            }
            let wanted: f64 = widest + theme.menu_width_over_text() + theme.menu_check_column()
            require(close_to(bounds.width, wanted, 0.001) || bounds.width == choice.frame().width,
                "the menu is {bounds.width} wide; AppKit wants {wanted}")
            let tall: f64 = 3.0 * theme.menu_row_height() + theme.menu_padding() * 2.0
            require(close_to(bounds.height, tall, 0.001),
                "the menu is {bounds.height} tall; three rows and the padding want {tall}")
            // The chosen row lands on the control, which is what makes it a
            // pop-up button rather than a drop-down.
            let chosen_top: f64 = bounds.y + theme.menu_padding() + theme.menu_row_height()
            require(close_to(chosen_top, (choice.frame().height - theme.menu_row_height()) / 2.0, 0.001),
                "the chosen row opens at {chosen_top} instead of over the control")
        }
    }
    io.println("ok popup menu: AppKit's width, row height and placement over the control")
    return ok(true)
}

fn labels(node: render.RenderObject, out: List<render.RenderObject>) {
    if node.role() == "text" { out.push(node) }
    // A row's text lives in the row button's template, not among its children.
    match node.visual() { some(part) => { labels(part, out) } none => {} }
    for index: int in 0..node.child_count() {
        match node.child_at(index) { some(child) => { labels(child, out) } none => {} }
    }
}

/// A menu row is 24 points whatever the control size, so its text is centred in
/// the row. Taking the owning control's baseline put a large popup's text two
/// points low and a mini popup's three and a half points high.
fn menu_rows_are_centred(scene: cortado_skia.Scene) -> Result<bool> {
    let context: render.UiContext = scene.context()
    let theme: render.Theme = context.theme()
    let root: widgets.Container = scene.root()
    for size: int in sizes() {
        theme.set_control_size(size)?
        for root.count() > 0 { root.remove(root.count() - 1)? }
        let combo: widgets.ComboBox = new widgets.ComboBox(some(context))
        combo.set_items(["Espresso", "Latte", "Cortado"])?
        combo.select(1)?
        combo.set_frame(geometry.Rect.of(20.0, 60.0, 150.0, theme.control_height()))?
        root.add(combo)?
        scene.resize(geometry.Size.of(400.0, 240.0), 2.0)?
        scene.refresh()?
        context.focus(combo.handle().raw)?
        context.dispatch(events.UiEvent.of(events.EventKind.activate, combo.handle()))?
        scene.refresh()?
        let sheet: render.RenderObject = context.popups().root().expect("an open menu")
        var found: List<render.RenderObject> = []
        labels(sheet, found)
        require(found.len() == 3, "the menu drew {found.len()} row labels, not three")
        let line: f64 = render.Theme.line_height(theme.menu_font_size())
        let wanted: f64 = (theme.menu_row_height() - line) / 2.0 + render.Theme.ascent(theme.menu_font_size())
        for label: render.RenderObject in found {
            require(close_to(label.real(host.P_BASELINE)?, wanted, 0.001),
                "a menu row at size {size} put its text on {label.real(host.P_BASELINE)?}, not {wanted}")
            require(close_to(label.frame().height, theme.menu_row_height(), 0.001),
                "a menu row at size {size} is {label.frame().height} tall, not {theme.menu_row_height()}")
        }
        // The same row height at every size is the thing that makes the
        // control baseline wrong for it.
        require(close_to(theme.menu_row_height(), 24.0, 0.001), "a menu row left 24 points at size {size}")
        combo.render_object()?.dismiss_popup()
        scene.refresh()?
    }
    theme.set_control_size(2)?
    io.println("ok menu rows: text centred in a 24 point row at every control size")
    return ok(true)
}

// ------------------------------------- 6. the offset a drawing travels by
fn offsets_are_checked(scene: cortado_skia.Scene) -> Result<bool> {
    let context: render.UiContext = scene.context()
    let root: widgets.Container = scene.root()
    for root.count() > 0 { root.remove(root.count() - 1)? }
    let toggle: widgets.Switch = new widgets.Switch(some(context))
    toggle.set_frame(geometry.Rect.of(0.0, 0.0, 54.0, 24.0))?
    root.add(toggle)?
    scene.refresh()?
    let marks: List<render.RenderObject> = control_drawings(toggle)?
    let knob: render.RenderObject = marks[1]
    // The knob carries a transition, so a new offset is where it is going;
    // one frame past the duration is where it has arrived.
    knob.set_real(visual.OFFSET_X, 0.0 - 12.5)?
    knob.set_real(visual.OFFSET_Y, 3.0)?
    scene.advance(1.0)?
    require(close_to(knob.real(visual.OFFSET_X)?, 0.0 - 12.5, 0.001),
        "a drawing refused a negative offset: {knob.real(visual.OFFSET_X)?}")
    require(close_to(knob.real(visual.OFFSET_Y)?, 3.0, 0.001), "a drawing lost its vertical offset")
    match knob.set_real(visual.OFFSET_X, 1000000.0) {
        ok(_) => { panic("a drawing accepted an offset off the world") }
        err(problem) => { require(problem.kind == "out_of_range", "wrong refusal: {problem.kind}") }
    }
    io.println("ok drawing offsets: signed, bounded, and read back where they were put")
    return ok(true)
}

// -------------------------- 7. the baseline a paragraph says it will paint on
fn baseline_is_where_it_paints(scene: cortado_skia.Scene) -> Result<bool> {
    // Asking for a baseline and painting on a different one is the defect this
    // pins: the shaper reports a face's metrics and lays out on the rounded
    // ones, so the number a control places text with has to be the second.
    for size: f64 in [9.0, 11.0, 13.0, 17.0, 22.0, 26.0] {
        let style: paint.TextStyle = paint.TextStyle { size: size }
        let run: paint.Paragraph = scene.renderer().styled_paragraph("HH", style, -1.0, 0x000000ff)?
        let metrics: paint.LineMetrics = run.metrics()
        // The Beans side reports the ascent as a negative rise, the way a
        // glyph run does; the baseline is the distance down to it.
        let rise: f64 = 0.0 - metrics.ascent
        let rounded: f64 = (rise + 0.5).floor()
        require(close_to(metrics.baseline, rounded, 0.001),
            "at {size}pt the baseline reads {metrics.baseline}, not the {rounded} it lays out on")
        require(metrics.baseline <= metrics.height,
            "a baseline outside its own line box at {size}pt")
    }
    io.println("ok text metrics: the baseline a run reports is the one it paints on")
    return ok(true)
}

fn verify() -> Result<bool> {
    let scene: cortado_skia.Scene = new cortado_skia.Scene(geometry.Size.of(200.0, 80.0), 41)
    radio_is_concentric(scene)?
    sizes_move_everything(scene)?
    field_sits_on_its_baseline(scene)?
    switch_motion(scene)?
    switch_press_motion(scene)?
    menu_matches_appkit(scene)?
    menu_rows_are_centred(scene)?
    offsets_are_checked(scene)?
    baseline_is_where_it_paints(scene)?
    scene.close()
    io.println("ok macOS appearance: geometry, control sizes, baselines, motion and the menu")
    return ok(true)
}
fn main() { match verify() { ok(_) => {} err(problem) => { panic(problem.msg) } } }
