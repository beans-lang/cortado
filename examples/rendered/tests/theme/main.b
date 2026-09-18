package main

import cortado_skia
import cortado.component
import cortado.geometry
import cortado.render
import cortado.widgets
import cortado.host
import {ControlsPage} from rendered_demo.generated.site
import std.io

fn require(value: bool, message: string) { if !value { panic(message) } }

fn find(root: widgets.Widget, kind: widgets.WidgetKind) -> Option<widgets.Widget> {
    if root.kind() == kind { return some(root) }
    for child: widgets.Widget in root.children() {
        match find(child, kind) { some(found) => { return some(found) } none => {} }
    }
    return none
}

/// Every colour here is a flat pixel of a pinned AppKit capture; the captures
/// and what they could not answer are in tools/reference/README.md.
fn tokens() -> Result<bool> {
    let theme: render.Theme = new render.Theme()
    require(!theme.is_dark(), "a new theme is light")
    require(theme.accent() == 0x007affff, "light accent is controlAccent")
    require(theme.foreground() == 0x000000d8, "light label is 85% black, not pure black")
    require(theme.background() == 0xffffffff, "light window is white")
    require(theme.card() == 0xffffffff, "light content area is white")
    // Read off the pinned captures rather than a colour lookup: an NSButton's
    // bezel paints ebebeb at every control size, in every state that is not
    // pressed or disabled. See tools/reference/README.md.
    require(theme.surface() == 0xebebebff, "light bezel, as a push button paints it")
    require(theme.separator() == 0x00000019, "light separator carries its alpha")
    require(theme.secondary_label() == 0x0000007f, "light secondary label carries its alpha")
    require(theme.selection() == 0x0064e1ff, "light row selection")

    let before: int = theme.version()
    theme.set_dark(true)
    require(theme.version() > before, "flipping appearance moves the revision")
    require(theme.is_dark(), "the theme is dark")
    require(theme.accent() == 0x007affff, "controlAccent does not change with appearance")
    require(theme.foreground() == 0xffffffd8, "dark label is 85% white")
    require(theme.background() == 0x1e1e1eff, "dark window is 1e1e1e, not black")
    require(theme.card() == 0x1e1e1eff, "dark content area matches the window")
    require(theme.surface() == 0x303030ff, "dark bezel, as a push button paints it")
    require(theme.separator() == 0xffffff19, "dark separator carries its alpha")
    require(theme.selection() == 0x0059d1ff, "dark row selection")
    // A dark knob is not white: the capture reads e1e1e1 off an NSSwitch.
    require(theme.knob() == 0xe1e1e1ff, "a dark knob is dimmed, not white")
    require(theme.on_accent() == 0xffffffff, "text on accent stays white")

    let steady: int = theme.version()
    theme.set_dark(true)
    require(theme.version() == steady, "setting the same appearance is not a change")

    // The type scale and the metrics are macOS's own, at the regular control
    // size a new theme starts on. Every number here is in build/reference:
    // the sizes from fonts.json, the heights from geometry.json, the switch
    // from its 4x capture, the corner from height/4 - 0.5.
    require(theme.body() == 13.0 && theme.font_size() == 13.0, "body text is systemFontSize")
    require(theme.large_title() == 26.0 && theme.footnote() == 10.0, "the type scale is macOS's")
    require(theme.control_height() == 24.0, "a regular control is 24pt tall")
    require(theme.row_height() == 24.0, "a list row is NSTableView's 24pt")
    require(theme.radius_medium() == 5.5, "a bezel corner is height/4 - 0.5")
    require(theme.switch_width() == 54.0 && theme.switch_height() == 24.0, "a switch is 54 by 24")
    // A control size moves them all together, and nothing else does.
    theme.set_control_size(1)?
    require(theme.font_size() == 11.0 && theme.control_height() == 20.0 &&
            theme.field_height() == 22.0 && theme.radio_dot() == 5.0,
            "the small control size did not move every metric with it")
    theme.set_control_size(2)?
    require(theme.capsule() > theme.control_height(), "a capsule radius outgrows any control")
    return ok(true)
}

/// set_colors still wins over the appearance, and only for the four it names.
fn overrides() -> Result<bool> {
    let theme: render.Theme = new render.Theme()
    theme.set_colors(0x102030ff, 0x405060ff, 0x708090ff, 0xa0b0c0ff)
    theme.set_dark(true)
    require(theme.background() == 0x102030ff, "an override outlives an appearance change")
    require(theme.accent() == 0x708090ff, "the accent override holds")
    require(theme.card() == 0x1e1e1eff, "an unnamed token still follows the appearance")
    require(theme.separator() == 0xffffff19, "separator still follows the appearance")
    return ok(true)
}

/// A template must re-read its tokens when the theme moves, or dark mode
/// stops at the page background and never reaches a control.
pub class Probe extends component.ControlTemplate {
    pub fn init() { super.init() }
    pub override fn render(into: component.Builder) {}
}

fn templates_follow_the_theme() -> Result<bool> {
    let view: ControlsPage = new ControlsPage()
    let scene: cortado_skia.Scene = new cortado_skia.Scene(geometry.Size.of(600.0, 680.0))
    scene.show(view)?
    let theme: render.Theme = scene.context().theme()
    let toggle: widgets.Widget = find(scene.root(), widgets.WidgetKind.switch).expect("switch")
    let object: render.RenderObject = toggle.render_object()?

    let probe: Probe = new Probe()
    probe.update(object, theme)
    require(probe.card == "#ffffffff", "a template starts on the light card")
    require(probe.surface == "#ebebebff", "a template starts on the light bezel")
    require(probe.track_off == "#e6e6e6ff", "a template starts on the light track")

    theme.set_dark(true)
    probe.update(object, theme)
    require(probe.card == "#1e1e1eff", "a template re-reads its card when the theme turns dark")
    require(probe.track_off == "#343434ff", "a template re-reads its track when the theme turns dark")
    require(probe.ink == "#ffffffd8", "a template re-reads its ink when the theme turns dark")
    require(probe.surface == "#303030ff", "a template re-reads its bezel when the theme turns dark")
    require(scene.refresh()?, "turning the theme dark repaints the scene")

    // A theme move that leaves fill, ink and accent alone still has to reach
    // the rest of the tokens; only the revision can see that one.
    let quiet: int = theme.background()
    theme.set_colors(0x123456ff, theme.foreground(), theme.accent(), theme.surface())
    require(theme.background() != quiet, "the override changed the background")
    probe.update(object, theme)
    require(probe.background == "#123456ff", "a token outside the compared set still refreshes")
    scene.close()
    return ok(true)
}

/// The shared backend used to refuse alignment outright while every native
/// host honoured it, so a centred label was a backend disagreement.
fn labels_take_alignment() -> Result<bool> {
    let view: ControlsPage = new ControlsPage()
    let scene: cortado_skia.Scene = new cortado_skia.Scene(geometry.Size.of(600.0, 680.0))
    scene.show(view)?
    let label: widgets.Widget = find(scene.root(), widgets.WidgetKind.label).expect("label")
    let object: render.RenderObject = label.render_object()?
    require(object.integer(host.P_ALIGNMENT)? == 0, "a label starts leading")
    require(object.set_integer(host.P_ALIGNMENT, 1)?, "centre was refused")
    require(object.integer(host.P_ALIGNMENT)? == 1, "centre did not stick")
    require(object.set_integer(host.P_ALIGNMENT, 2)?, "trailing was refused")
    match object.set_integer(host.P_ALIGNMENT, 3) {
        ok(_) => { panic("a fourth alignment was accepted") } err(_) => {}
    }
    match object.set_integer(host.P_ALIGNMENT, -1) {
        ok(_) => { panic("a negative alignment was accepted") } err(_) => {}
    }
    require(object.integer(host.P_ALIGNMENT)? == 2, "a refused alignment overwrote the last good one")
    scene.close()
    return ok(true)
}

fn verify() -> Result<bool> {
    tokens()?
    overrides()?
    templates_follow_the_theme()?
    labels_take_alignment()?
    io.println("ok theme: macOS tokens, appearance switching, overrides, template refresh, label alignment")
    return ok(true)
}

fn main() {
    match verify() { ok(value) => {} err(problem) => { panic("theme test failed") } }
}
