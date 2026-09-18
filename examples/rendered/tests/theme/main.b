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

/// Every colour here came out of UIKit; tools/read_apple_tokens.swift prints them.
fn tokens() -> Result<bool> {
    let theme: render.Theme = new render.Theme()
    require(!theme.is_dark(), "a new theme is light")
    require(theme.accent() == 0x0088ffff, "light accent is systemBlue")
    require(theme.foreground() == 0x000000ff, "light label is black")
    require(theme.background() == 0xffffffff, "light background is white")
    require(theme.grouped_background() == 0xf2f2f7ff, "light grouped background")
    require(theme.card() == 0xffffffff, "light card is white")
    require(theme.separator() == 0x3c3c431f, "light separator carries its alpha")
    require(theme.secondary_label() == 0x3c3c4399, "light secondary label carries its alpha")
    require(theme.gray6() == 0xf2f2f7ff, "light gray 6")

    let before: int = theme.version()
    theme.set_dark(true)
    require(theme.version() > before, "flipping appearance moves the revision")
    require(theme.is_dark(), "the theme is dark")
    require(theme.accent() == 0x0091ffff, "dark accent is the darker systemBlue")
    require(theme.foreground() == 0xffffffff, "dark label is white")
    require(theme.background() == 0x000000ff, "dark background is black")
    require(theme.grouped_background() == 0x000000ff, "dark grouped background is black")
    require(theme.card() == 0x1c1c1eff, "a dark card lifts off black")
    require(theme.separator() == 0x54545880, "dark separator carries its alpha")
    require(theme.gray6() == 0x1c1c1eff, "dark gray 6")
    require(theme.knob() == 0xffffffff, "a knob stays white in the dark")
    require(theme.on_accent() == 0xffffffff, "text on accent stays white")

    let steady: int = theme.version()
    theme.set_dark(true)
    require(theme.version() == steady, "setting the same appearance is not a change")

    // The type scale and metrics are iOS point sizes, not the old 14pt guesses.
    require(theme.body() == 17.0 && theme.font_size() == 17.0, "body text is 17pt")
    require(theme.large_title() == 34.0 && theme.footnote() == 13.0, "the type scale is Apple's")
    require(theme.control_height() == 34.0, "a control is 34pt tall")
    require(theme.switch_width() == 61.0 && theme.switch_height() == 28.0, "a switch is 61x28")
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
    require(theme.card() == 0x1c1c1eff, "an unnamed token still follows the appearance")
    require(theme.separator() == 0x54545880, "separator still follows the appearance")
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
    require(probe.track_off == "#e9e9eaff", "a template starts on the light track")

    theme.set_dark(true)
    probe.update(object, theme)
    require(probe.card == "#1c1c1eff", "a template re-reads its card when the theme turns dark")
    require(probe.track_off == "#39393dff", "a template re-reads its track when the theme turns dark")
    require(probe.ink == "#ffffffff", "a template re-reads its ink when the theme turns dark")
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
    io.println("ok theme: iOS tokens, appearance switching, overrides, template refresh, label alignment")
    return ok(true)
}

fn main() {
    match verify() { ok(value) => {} err(problem) => { panic("theme test failed") } }
}
