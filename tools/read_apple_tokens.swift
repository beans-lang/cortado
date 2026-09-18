// Prints the macOS system colours, small-control type scale and metrics behind
// render/theme.b.  swift tools/read_apple_tokens.swift
import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let light = NSAppearance(named: .aqua)!
let dark = NSAppearance(named: .darkAqua)!

func hex(_ color: NSColor) -> String {
    guard let s = color.usingColorSpace(.sRGB) else { return "n/a" }
    return String(format: "0x%02x%02x%02x%02x", Int((s.redComponent * 255).rounded()),
                  Int((s.greenComponent * 255).rounded()), Int((s.blueComponent * 255).rounded()),
                  Int((s.alphaComponent * 255).rounded()))
}
func both(_ name: String, _ pick: () -> NSColor) {
    var l = "", d = ""
    light.performAsCurrentDrawingAppearance { l = hex(pick()) }
    dark.performAsCurrentDrawingAppearance { d = hex(pick()) }
    print("pub fn \(name)() -> int { return self.pick(\(l), \(d)) }")
}

print("// ---- semantic colours, straight from NSColor")
both("accent") { .controlAccentColor }
both("destructive") { .systemRed }
both("success") { .systemGreen }
both("warning") { .systemOrange }
both("foreground") { .labelColor }
both("secondary_label") { .secondaryLabelColor }
both("tertiary_label") { .tertiaryLabelColor }
both("quaternary_label") { .quaternaryLabelColor }
both("placeholder") { .placeholderTextColor }
both("disabled_label") { .disabledControlTextColor }
both("background") { .windowBackgroundColor }
both("card") { .controlBackgroundColor }
both("separator") { .separatorColor }
both("grid") { .gridColor }
both("selection") { .selectedContentBackgroundColor }
both("quiet_selection") { .unemphasizedSelectedContentBackgroundColor }
both("text_selection") { .selectedTextBackgroundColor }
both("link") { .linkColor }

print("// ---- bezel fills, sampled from a real control (NSColor.control is translucent)")
func bezel(_ appearance: NSAppearance, _ make: () -> NSControl, _ page: NSColor) -> String {
    var answer = "n/a"
    appearance.performAsCurrentDrawingAppearance {
        let control = make()
        control.appearance = appearance
        control.sizeToFit()
        let host = NSView(frame: control.bounds)
        host.appearance = appearance
        host.wantsLayer = true
        host.layer?.backgroundColor = page.cgColor
        host.addSubview(control)
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        if let p = rep.colorAt(x: rep.pixelsWide / 2, y: rep.pixelsHigh / 2) { answer = hex(p) }
    }
    return answer
}
func push() -> NSControl {
    let b = NSButton(title: "Button", target: nil, action: nil)
    b.bezelStyle = .push; b.controlSize = .small
    return b
}
var pageLight = NSColor.white, pageDark = NSColor.black
light.performAsCurrentDrawingAppearance { pageLight = NSColor.windowBackgroundColor }
dark.performAsCurrentDrawingAppearance { pageDark = NSColor.windowBackgroundColor }
print("pub fn surface() -> int { return self.pick(\(bezel(light, push, pageLight)), \(bezel(dark, push, pageDark))) }")
both("field") { .textBackgroundColor }

print("// ---- type scale: the small control size, 11pt")
let layout = NSLayoutManager()
for size in [9.0, 10.0, 11.0, 12.0, 13.0, 15.0, 17.0, 22.0] {
    let f = NSFont.systemFont(ofSize: size)
    print(String(format: "// %.0fpt lineHeight %.0f", size, layout.defaultLineHeight(for: f)))
}
print(String(format: "// systemFontSize %.0f  smallSystemFontSize %.0f  labelFontSize %.0f",
             NSFont.systemFontSize, NSFont.smallSystemFontSize, NSFont.labelFontSize))

print("// ---- metrics, control size small")
for (name, cs) in [("mini", NSControl.ControlSize.mini), ("small", .small), ("regular", .regular)] {
    let b = NSButton(title: "Button", target: nil, action: nil); b.bezelStyle = .push
    b.controlSize = cs; b.sizeToFit()
    let pop = NSPopUpButton(); pop.addItem(withTitle: "Choose"); pop.controlSize = cs; pop.sizeToFit()
    let seg = NSSegmentedControl(labels: ["a","b"], trackingMode: .selectOne, target: nil, action: nil)
    seg.controlSize = cs; seg.sizeToFit()
    let cb = NSButton(checkboxWithTitle: "C", target: nil, action: nil); cb.controlSize = cs; cb.sizeToFit()
    let sl = NSSlider(); sl.controlSize = cs; sl.sizeToFit()
    let st = NSStepper(); st.controlSize = cs; st.sizeToFit()
    let sw = NSSwitch(); sw.controlSize = cs; sw.sizeToFit()
    let bar = NSProgressIndicator(); bar.style = .bar; bar.controlSize = cs; bar.sizeToFit()
    print(String(format: "// %-7@ button %.0f  popup %.0f  segmented %.0f  check %.0f  slider %.0f  stepper %.0fx%.0f  switch %.0fx%.0f  bar %.0f",
                 name as NSString, b.frame.height, pop.frame.height, seg.frame.height, cb.frame.height,
                 sl.frame.height, st.frame.width, st.frame.height, sw.frame.width, sw.frame.height, bar.frame.height))
}
