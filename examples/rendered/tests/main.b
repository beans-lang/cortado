package main

import cortado_skia
import cortado.geometry
import cortado.widgets
import cortado.render
import cortado.events
import cortado.host
import cortado.component
import cortado.templates
import cortado.visual
import {Screen, CoffeeButton} from rendered_demo.generated.site
import std.io

class CoffeeTemplates implements component.TemplateFactory {
    defaults: templates.DefaultTemplates = new templates.DefaultTemplates()
    pub fn init() {}
    pub fn create(control: render.RenderObject) -> Option<component.ControlTemplate> {
        match control as? render.ButtonRender {
            some(_) => { return some(new CoffeeButton()) }
            none => { return self.defaults.create(control) }
        }
    }
}

fn require(value: bool, message: string) { if !value { panic(message) } }

fn find(root: widgets.Widget, kind: widgets.WidgetKind) -> Option<widgets.Widget> {
    if root.kind() == kind { return some(root) }
    for child: widgets.Widget in root.children() {
        match find(child, kind) { some(found) => { return some(found) } none => {} }
    }
    return none
}

fn verify() -> Result<bool> {
    let view: Screen = new Screen()
    let scene: cortado_skia.Scene = new cortado_skia.Scene(geometry.Size.of(520.0, 470.0))
    require(scene.show(view)?, "first screen did not paint")
    require(!scene.refresh()?, "idle screen repainted")
    let button: widgets.Widget = find(scene.root(), widgets.WidgetKind.button).expect("button from .bx")
    let field: widgets.Widget = find(scene.root(), widgets.WidgetKind.text_field).expect("text field from .bx")
    let scroller: widgets.Widget = find(scene.root(), widgets.WidgetKind.scroll_view).expect("scroller from .bx")
    let button_id: u64 = button.handle().raw
    let button_frame: geometry.Rect = scene.global_frame(button.render_object()?)?
    let button_point: geometry.Point = geometry.Point.at(button_frame.x + button_frame.width / 2.0,
                                                         button_frame.y + button_frame.height / 2.0)
    let before_hover_semantics: int = scene.context().invalidation().semantics_version()
    scene.pointer(events.EventKind.pointer_move, button_point)?
    require(button.render_object()?.hovered(), "pointer did not hover the default button")
    let default_root: render.RenderObject = button.render_object()?.visual().expect("default button visual")
    let hover_color: int = default_root.child_at(0).expect("default button layout").integer(host.P_BG_COLOR)?
    require(hover_color == 0xdbe5ffff,
            "default .bx button did not show hover color")
    require(scene.context().invalidation().semantics_version() == before_hover_semantics,
            "hover changed button semantics")
    scene.pointer(events.EventKind.pointer_move, geometry.Point.at(-1.0, -1.0))?
    require(!button.render_object()?.hovered(), "default button stayed hovered after leave")
    require(default_root.child_at(0).expect("default button layout").integer(host.P_BG_COLOR)? != 0xdbe5ffff,
            "default button kept its hover color after leave")
    require(scene.context().invalidation().semantics_version() == before_hover_semantics,
            "leaving button changed semantics")
    scene.context().focus(button_id)?
    require(scene.key(events.EventKind.key_down, events.Key.space)?, "activation did not paint")
    require(view.orders == 1, ".bx click binding did not run")
    require(find(scene.root(), widgets.WidgetKind.button).expect("retained button").handle().raw == button_id,
            "component refresh replaced keyed button")
    require(button.a11y_role()? == "button", "template changed control semantics")
    scene.context().focus(field.handle().raw)?
    scene.key(events.EventKind.key_down, events.Key.character, "Café 👩‍💻")?
    require(field.display_text()? == "Café 👩‍💻", "key input did not edit field")
    scene.key(events.EventKind.key_down, events.Key.ret)?
    require(view.name == "Café 👩‍💻" && field.display_text()? == view.name, "two-way .bx text binding failed")
    scene.key(events.EventKind.key_down, events.Key.backspace)?
    scene.key(events.EventKind.key_down, events.Key.ret)?
    require(view.name == "Café ", "key editing split emoji")
    scene.key(events.EventKind.key_down, events.Key.character, "a", host.MOD_COMMAND)?
    let editor: render.TextFieldRender = (field.render_object()? as? render.TextFieldRender).expect("shared text editor")
    require(editor.selection_anchor() == 0 && editor.selection_caret() == view.name.len(), "Select All failed")
    scene.key(events.EventKind.key_down, events.Key.character, "Tea")?
    scene.key(events.EventKind.key_down, events.Key.character, "z", host.MOD_COMMAND)?
    require(field.display_text()? == "Café ", "keyboard undo failed")
    require(!scene.refresh()?, "settled binding kept repainting")
    let scroll: render.ScrollRender = (scroller.render_object()? as? render.ScrollRender).expect("shared scroll object")
    require(scroll.content_size().height > scroll.frame().height, "scroll layout measured only the viewport")
    let scroll_bounds: geometry.Rect = scene.global_frame(scroll)?
    require(scene.scroll(geometry.Point.at(scroll_bounds.x + 20.0, scroll_bounds.y + 20.0), 0.0, 90.0)?, "wheel did not bubble from content to scroll view")
    require(scroll.child_offset().y == -90.0, "scroll offset ignored")
    require(!scene.refresh()?, "idle scroller repainted")
    scene.use_templates(new CoffeeTemplates())
    require(scene.refresh()?, "template replacement did not paint")
    require(button.handle().raw == button_id && button.a11y_role()? == "button", "template replaced behavior identity")
    scene.context().focus(button_id)?
    scene.key(events.EventKind.key_down, events.Key.space)?
    require(view.orders == 2, "custom .bx template lost keyboard activation")
    require(!scene.refresh()?, "custom template kept repainting")
    let coffee_root: render.RenderObject = button.render_object()?.visual().expect("custom button visual")
    let coffee_box: render.RenderObject = coffee_root.child_at(0).expect("custom button box")
    let coffee_shape: render.RenderObject = coffee_box.child_at(0).expect("custom button shape")
    let coffee_before: int = coffee_shape.integer(visual.FILL)?
    require(coffee_before == 0x654632ff && coffee_shape.frame().width > 0.0,
            "custom drawing background was not laid out")
    let coffee_semantics: int = scene.context().invalidation().semantics_version()
    scene.pointer(events.EventKind.pointer_move, button_point)?
    require(button.render_object()?.hovered() && scene.has_active_animations(),
            "custom .bx hover did not schedule its visual transition")
    require(coffee_shape.integer(visual.FILL)? == coffee_before,
            "custom hover transition jumped before a frame")
    require(scene.context().invalidation().semantics_version() == coffee_semantics,
            "custom hover changed semantics")
    scene.advance(0.09)?
    let coffee_middle: int = coffee_shape.integer(visual.FILL)?
    require(coffee_middle != coffee_before && coffee_middle != 0x98643cff,
            "custom hover color did not interpolate")
    require(scene.context().invalidation().semantics_version() == coffee_semantics,
            "custom color frame changed semantics")
    scene.advance(0.09)?
    require(coffee_shape.integer(visual.FILL)? == 0x98643cff && !scene.has_active_animations(),
            "custom hover transition did not settle")
    require(scene.context().invalidation().semantics_version() == coffee_semantics,
            "custom color completion changed semantics")
    scene.pointer(events.EventKind.pointer_move, geometry.Point.at(-1.0, -1.0))?
    require(!button.render_object()?.hovered() && scene.has_active_animations(),
            "custom hover did not reverse on leave")
    scene.advance(0.18)?
    require(coffee_shape.integer(visual.FILL)? == coffee_before && !scene.has_active_animations(),
            "custom hover did not return to its idle color")
    require(scene.context().invalidation().semantics_version() == coffee_semantics,
            "custom hover leave changed semantics")
    scene.key(events.EventKind.key_down, events.Key.tab, "", host.MOD_SHIFT)?
    require(field.render_object()?.focused(), "Shift-Tab did not move backward")
    scene.resize(geometry.Size.of(520.0, 470.0), 2.0)?
    let pixels: widgets.Snapshot = scene.renderer().snapshot()?
    require(pixels.width == 1040 && pixels.height == 940, "display scale did not size pixels")
    scene.renderer().write_png("build/rendered-tested.png")?
    scene.close(); scene.close()
    require(scene.context().registry().count() == 0, "scene leaked registered nodes")
    require(scene.context().router().registered() == 0 && scene.context().router().watching() == 0,
            "scene leaked event callbacks")
    require(!button.is_alive(), "scene close left a live control")
    io.println("ok .bx templates, identity, bindings, keyboard editing, scrolling, scale, idle, teardown")
    return ok(true)
}
fn main() { match verify() { ok(_) => {} err(problem) => { panic(problem.msg) } } }
