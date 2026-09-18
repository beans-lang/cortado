package main

import cortado_skia
import cortado.component
import cortado.geometry
import cortado.widgets
import cortado.render
import cortado.host
import {AccessibilityPage} from rendered_demo.generated.site
import std.io

fn require(value: bool, message: string) { if !value { panic(message) } }
fn find(root: widgets.Widget, kind: widgets.WidgetKind) -> Option<widgets.Widget> {
    if root.kind() == kind { return some(root) }
    for child: widgets.Widget in root.children() {
        match find(child, kind) { some(found) => { return some(found) } none => {} }
    }
    return none
}
fn named(scene: cortado_skia.Scene, id: u64) -> render.SemanticsNode {
    for node: render.SemanticsNode in scene.semantics() { if node.id() == id { return node } }
    panic("semantics node is missing")
}
fn verify() -> Result<bool> {
    let page: AccessibilityPage = new AccessibilityPage()
    let scene: cortado_skia.Scene = new cortado_skia.Scene(geometry.Size.of(560.0, 680.0))
    scene.show(page)?
    let combo: widgets.Widget = find(scene.root(), widgets.WidgetKind.combo_box).expect("combo")
    let name: widgets.Widget = find(scene.root(), widgets.WidgetKind.text_field).expect("name")
    let secret: widgets.Widget = find(scene.root(), widgets.WidgetKind.secure_field).expect("secret")
    require(named(scene, combo.handle().raw).label() == "Drink", "ComboBox lost markup accessibility name")
    require(named(scene, name.handle().raw).label() == "Name", "TextField lost markup accessibility name")
    require(named(scene, secret.handle().raw).label() == "Private code", "SecureField lost markup accessibility name")
    page.name_label = "Full name"
    page.request_render()
    scene.refresh()?
    require(named(scene, name.handle().raw).label() == "Full name", "changed accessibility name stayed stale")
    page.hide_name = true
    page.request_render()
    scene.refresh()?
    require(name.is_hidden()?, "hidden and a11y_label collided in the attribute table")
    page.hide_name = false
    page.request_render()
    scene.refresh()?
    require(!name.is_hidden()? && named(scene, name.handle().raw).label() == "Full name",
            "restoring hidden lost the accessibility name")
    page.secret = "hidden"
    page.request_render()
    scene.refresh()?
    require(named(scene, secret.handle().raw).value() == "", "SecureField exposed private text")
    let reset: component.Attribute = component.Attribute.default_for(host.S_A11Y_LABEL, component.AttributeKind.text)
    component.WidgetMaker.write(name, reset)?
    require(named(scene, name.handle().raw).label() == "", "removed accessibility name was not reset")
    scene.close()
    io.println("ok markup accessibility names, secure value, and reset")
    return ok(true)
}

fn main() { match verify() { ok(_) => {} err(problem) => { panic(problem.msg) } } }
