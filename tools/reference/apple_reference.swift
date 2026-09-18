// Reads the real AppKit controls on this Mac and writes the reference the
// shared theme is measured against. Native code is allowed here; it never ships.
// Runs inside an app bundle so windows can become key — see capture.sh.
import AppKit
import CoreText

let outRoot = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/reference"
try? FileManager.default.createDirectory(atPath: outRoot + "/shots", withIntermediateDirectories: true)

let aqua = NSAppearance(named: .aqua)!
let darkAqua = NSAppearance(named: .darkAqua)!

// --------------------------------------------------------------- JSON writing
func quote(_ s: String) -> String {
    var out = "\""
    for ch in s.unicodeScalars {
        switch ch {
        case "\"": out += "\\\""
        case "\\": out += "\\\\"
        case "\n": out += "\\n"
        default: out.unicodeScalars.append(ch)
        }
    }
    return out + "\""
}
func fmt(_ v: Double) -> String {
    if v.isNaN || v.isInfinite { return "null" }
    if v == v.rounded() && abs(v) < 1e15 { return String(format: "%.1f", v) }
    return String(format: "%.4f", v)
}
func obj(_ pairs: [(String, String)]) -> String {
    "{" + pairs.map { "\(quote($0.0)): \($0.1)" }.joined(separator: ", ") + "}"
}

func hex(_ color: NSColor) -> String {
    guard let s = color.usingColorSpace(.sRGB) else { return "null" }
    return String(format: "\"%02x%02x%02x%02x\"",
                  Int((s.redComponent * 255).rounded()), Int((s.greenComponent * 255).rounded()),
                  Int((s.blueComponent * 255).rounded()), Int((s.alphaComponent * 255).rounded()))
}
func inAppearance<T>(_ a: NSAppearance, _ body: () -> T) -> T {
    var answer: T! = nil
    a.performAsCurrentDrawingAppearance { answer = body() }
    return answer
}
func weightOf(_ font: NSFont) -> Double {
    let traits = CTFontCopyTraits(font as CTFont) as NSDictionary
    return (traits[kCTFontWeightTrait] as? NSNumber)?.doubleValue ?? 0
}

// ============================================================ 1. system colours
let colourRoles: [(String, () -> NSColor)] = [
    ("controlAccent", { .controlAccentColor }),
    ("systemRed", { .systemRed }), ("systemGreen", { .systemGreen }),
    ("systemOrange", { .systemOrange }), ("systemYellow", { .systemYellow }),
    ("systemBlue", { .systemBlue }), ("systemPurple", { .systemPurple }),
    ("systemPink", { .systemPink }), ("systemTeal", { .systemTeal }),
    ("systemIndigo", { .systemIndigo }), ("systemBrown", { .systemBrown }),
    ("systemGray", { .systemGray }), ("systemMint", { .systemMint }),
    ("systemCyan", { .systemCyan }),
    ("label", { .labelColor }), ("secondaryLabel", { .secondaryLabelColor }),
    ("tertiaryLabel", { .tertiaryLabelColor }), ("quaternaryLabel", { .quaternaryLabelColor }),
    ("placeholderText", { .placeholderTextColor }), ("disabledControlText", { .disabledControlTextColor }),
    ("text", { .textColor }), ("selectedText", { .selectedTextColor }),
    ("selectedTextBackground", { .selectedTextBackgroundColor }),
    ("unemphasizedSelectedText", { .unemphasizedSelectedTextColor }),
    ("unemphasizedSelectedTextBackground", { .unemphasizedSelectedTextBackgroundColor }),
    ("windowBackground", { .windowBackgroundColor }),
    ("underPageBackground", { .underPageBackgroundColor }),
    ("controlBackground", { .controlBackgroundColor }),
    ("textBackground", { .textBackgroundColor }),
    ("control", { .controlColor }), ("controlText", { .controlTextColor }),
    ("selectedControl", { .selectedControlColor }), ("selectedControlText", { .selectedControlTextColor }),
    ("alternateSelectedControlText", { .alternateSelectedControlTextColor }),
    ("selectedContentBackground", { .selectedContentBackgroundColor }),
    ("unemphasizedSelectedContentBackground", { .unemphasizedSelectedContentBackgroundColor }),
    ("separator", { .separatorColor }), ("grid", { .gridColor }),
    ("headerText", { .headerTextColor }), ("link", { .linkColor }),
    ("keyboardFocusIndicator", { .keyboardFocusIndicatorColor }),
    ("shadow", { .shadowColor }), ("highlight", { .highlightColor }),
    ("findHighlight", { .findHighlightColor }),
]
func colourJSON() -> String {
    var rows: [String] = []
    for (name, pick) in colourRoles {
        rows.append("    " + obj([("role", quote(name)),
                                  ("light", inAppearance(aqua) { hex(pick()) }),
                                  ("dark", inAppearance(darkAqua) { hex(pick()) })]))
    }
    for (idx, c) in NSColor.alternatingContentBackgroundColors.enumerated() {
        rows.append("    " + obj([("role", quote("alternatingContentBackground\(idx)")),
                                  ("light", inAppearance(aqua) { hex(c) }),
                                  ("dark", inAppearance(darkAqua) { hex(c) })]))
    }
    return "{\n  \"colors\": [\n" + rows.joined(separator: ",\n") + "\n  ]\n}"
}

// ====================================================== 2. fonts and text metrics
func fontRow(_ label: String, _ font: NSFont) -> String {
    let layout = NSLayoutManager()
    let ct = font as CTFont
    // Tracking: what AppKit's own text measurement adds over raw glyph advances.
    let sample = "HHHHHHHHHHHHHHHHHHHH"
    let laidOut = (sample as NSString).size(withAttributes: [.font: font]).width
    var glyph = CGGlyph(0)
    var char: UniChar = UniChar(UnicodeScalar("H").value)
    CTFontGetGlyphsForCharacters(ct, &char, &glyph, 1)
    let advance = CTFontGetAdvancesForGlyphs(ct, .horizontal, &glyph, nil, 1)
    let tracking = (laidOut - advance * 20.0) / 19.0
    return "    " + obj([
        ("role", quote(label)), ("family", quote(font.familyName ?? "")),
        ("name", quote(font.fontName)), ("size", fmt(Double(font.pointSize))),
        ("weight", fmt(weightOf(font))),
        ("ascent", fmt(Double(CTFontGetAscent(ct)))), ("descent", fmt(Double(CTFontGetDescent(ct)))),
        ("leading", fmt(Double(CTFontGetLeading(ct)))),
        ("capHeight", fmt(Double(font.capHeight))), ("xHeight", fmt(Double(font.xHeight))),
        ("lineHeight", fmt(Double(layout.defaultLineHeight(for: font)))),
        ("advanceH", fmt(Double(advance))), ("tracking", fmt(tracking)),
        ("unitsPerEm", fmt(Double(CTFontGetUnitsPerEm(ct)))),
    ])
}
func fontJSON() -> String {
    var rows: [String] = []
    for (label, f) in [
        ("system", NSFont.systemFont(ofSize: NSFont.systemFontSize)),
        ("smallSystem", NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)),
        ("label", NSFont.systemFont(ofSize: NSFont.labelFontSize)),
        ("menu", NSFont.menuFont(ofSize: 0)), ("menuBar", NSFont.menuBarFont(ofSize: 0)),
        ("message", NSFont.messageFont(ofSize: 0)), ("toolTips", NSFont.toolTipsFont(ofSize: 0)),
        ("titleBar", NSFont.titleBarFont(ofSize: 0)), ("palette", NSFont.paletteFont(ofSize: 0)),
        ("controlContentMini", NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .mini))),
        ("controlContentSmall", NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .small))),
        ("controlContentRegular", NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .regular))),
        ("controlContentLarge", NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .large))),
    ] { rows.append(fontRow(label, f)) }
    for size in [8.0, 9.0, 10.0, 11.0, 12.0, 13.0, 14.0, 15.0, 16.0, 17.0, 18.0, 20.0, 22.0, 26.0, 28.0] {
        rows.append(fontRow("system@\(Int(size))", NSFont.systemFont(ofSize: size)))
        rows.append(fontRow("medium@\(Int(size))", NSFont.systemFont(ofSize: size, weight: .medium)))
        rows.append(fontRow("semibold@\(Int(size))", NSFont.systemFont(ofSize: size, weight: .semibold)))
        rows.append(fontRow("bold@\(Int(size))", NSFont.systemFont(ofSize: size, weight: .bold)))
    }
    let styles: [(String, NSFont.TextStyle)] = [
        ("largeTitle", .largeTitle), ("title1", .title1), ("title2", .title2), ("title3", .title3),
        ("headline", .headline), ("subheadline", .subheadline), ("body", .body),
        ("callout", .callout), ("footnote", .footnote), ("caption1", .caption1), ("caption2", .caption2),
    ]
    for (name, style) in styles { rows.append(fontRow("style.\(name)", NSFont.preferredFont(forTextStyle: style))) }
    return "{\n  \"fonts\": [\n" + rows.joined(separator: ",\n") + "\n  ]\n}"
}

// ============================================================ 3. the control set
let sizes: [(String, NSControl.ControlSize)] =
    [("mini", .mini), ("small", .small), ("regular", .regular), ("large", .large)]

/// `on` builds the checked/selected variant where the control has one.
func makers(_ cs: NSControl.ControlSize, on: Bool) -> [(String, NSView)] {
    func push(_ title: String) -> NSButton {
        let b = NSButton(title: title, target: nil, action: nil); b.bezelStyle = .push; return b
    }
    let defaulted = push("Default"); defaulted.keyEquivalent = "\r"
    let check = NSButton(checkboxWithTitle: "Check", target: nil, action: nil)
    check.state = on ? .on : .off
    let mixed = NSButton(checkboxWithTitle: "Mixed", target: nil, action: nil)
    mixed.allowsMixedState = true; mixed.state = .mixed
    let radio = NSButton(radioButtonWithTitle: "Radio", target: nil, action: nil)
    radio.state = on ? .on : .off
    let sw = NSSwitch(); sw.state = on ? .on : .off
    let seg = NSSegmentedControl(labels: ["One", "Two", "Three"], trackingMode: .selectOne, target: nil, action: nil)
    seg.selectedSegment = on ? 2 : 1
    let pop = NSPopUpButton(); pop.addItems(withTitles: ["Choose", "Other"])
    let pullDown = NSPopUpButton(frame: .zero, pullsDown: true); pullDown.addItems(withTitles: ["Actions", "One"])
    let combo = NSComboBox(); combo.addItems(withObjectValues: ["Alpha", "Beta"]); combo.stringValue = "Alpha"
    let field = NSTextField(string: "Text")
    let empty = NSTextField(string: ""); empty.placeholderString = "Placeholder"
    let secure = NSSecureTextField(string: "secret")
    let search = NSSearchField(string: on ? "coffee" : "")
    let slider = NSSlider(value: 0.45, minValue: 0, maxValue: 1, target: nil, action: nil)
    let bar = NSProgressIndicator(); bar.style = .bar; bar.isIndeterminate = false
    bar.minValue = 0; bar.maxValue = 100; bar.doubleValue = 45
    let level = NSLevelIndicator(); level.maxValue = 10; level.doubleValue = 6
    let disclosure = NSButton(title: "", target: nil, action: nil)
    disclosure.bezelStyle = .disclosure; disclosure.setButtonType(.pushOnPushOff)
    disclosure.state = on ? .on : .off
    let box = NSBox(); box.title = "Group"; box.titlePosition = .atTop
    box.setFrameSize(NSSize(width: 160, height: 80))
    let rows: [(String, NSView)] = [
        ("push_button", push("Button")), ("default_button", defaulted),
        ("check_box", check), ("mixed_check_box", mixed), ("radio_button", radio),
        ("switch_control", sw),
        ("popup_button", pop), ("pulldown_button", pullDown), ("combo_box", combo),
        ("segmented", seg),
        ("text_field", field), ("placeholder_field", empty),
        ("secure_field", secure), ("search_field", search),
        ("stepper", NSStepper()), ("slider", slider),
        ("progress_bar", bar), ("level_indicator", level),
        ("disclosure", disclosure), ("group_box", box),
    ]
    // Setting controlSize alone leaves the font at 13pt, so a mini bezel would be
    // captured with regular-size text. Interface Builder resizes it; so do we.
    let sized = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: cs))
    for (_, v) in rows {
        if let c = v as? NSControl {
            c.controlSize = cs
            if !(v is NSSwitch) && !(v is NSStepper) && !(v is NSSlider) && !(v is NSLevelIndicator) {
                c.font = sized
            }
        }
        if let p = v as? NSProgressIndicator { p.controlSize = cs }
    }
    return rows
}

// ============================================================== 4. geometry dump
func insetsOf(_ v: NSView) -> String {
    let i = v.alignmentRectInsets
    return obj([("top", fmt(Double(i.top))), ("left", fmt(Double(i.left))),
                ("bottom", fmt(Double(i.bottom))), ("right", fmt(Double(i.right)))])
}
func geometryJSON() -> String {
    var rows: [String] = []
    for (sizeName, cs) in sizes {
        for (name, view) in makers(cs, on: false) {
            if let control = view as? NSControl { control.sizeToFit() } else { view.setFrameSize(view.fittingSize) }
            var pairs: [(String, String)] = [
                ("control", quote(name)), ("size", quote(sizeName)),
                ("fitWidth", fmt(Double(view.frame.width))), ("fitHeight", fmt(Double(view.frame.height))),
                ("fittingWidth", fmt(Double(view.fittingSize.width))),
                ("fittingHeight", fmt(Double(view.fittingSize.height))),
                ("intrinsicWidth", fmt(Double(view.intrinsicContentSize.width))),
                ("intrinsicHeight", fmt(Double(view.intrinsicContentSize.height))),
                ("alignmentInsets", insetsOf(view)),
                ("baselineFromBottom", fmt(Double(view.baselineOffsetFromBottom))),
                ("firstBaselineFromTop", fmt(Double(view.firstBaselineOffsetFromTop))),
                ("lastBaselineFromBottom", fmt(Double(view.lastBaselineOffsetFromBottom))),
            ]
            if let control = view as? NSControl {
                if let font = control.font {
                    pairs.append(("font", quote(font.fontName)))
                    pairs.append(("fontSize", fmt(Double(font.pointSize))))
                    pairs.append(("fontWeight", fmt(weightOf(font))))
                }
                if let cell = control.cell {
                    let bounds = NSRect(origin: .zero, size: control.frame.size)
                    let drawing = cell.drawingRect(forBounds: bounds)
                    let title = cell.titleRect(forBounds: bounds)
                    pairs.append(("drawingRect", obj([("x", fmt(Double(drawing.minX))), ("y", fmt(Double(drawing.minY))),
                                                      ("w", fmt(Double(drawing.width))), ("h", fmt(Double(drawing.height)))])))
                    pairs.append(("titleRect", obj([("x", fmt(Double(title.minX))), ("y", fmt(Double(title.minY))),
                                                    ("w", fmt(Double(title.width))), ("h", fmt(Double(title.height)))])))
                }
            }
            rows.append("    " + obj(pairs))
        }
    }
    var extras: [String] = []
    func extra(_ name: String, _ pairs: [(String, String)]) {
        extras.append("    " + obj([("item", quote(name))] + pairs))
    }
    extra("scroller", [
        ("widthRegular", fmt(Double(NSScroller.scrollerWidth(for: .regular, scrollerStyle: .overlay)))),
        ("widthSmall", fmt(Double(NSScroller.scrollerWidth(for: .small, scrollerStyle: .overlay)))),
        ("widthLegacyRegular", fmt(Double(NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)))),
    ])
    let table = NSTableView()
    extra("table", [("rowHeight", fmt(Double(table.rowHeight))),
                    ("intercellWidth", fmt(Double(table.intercellSpacing.width))),
                    ("intercellHeight", fmt(Double(table.intercellSpacing.height))),
                    ("headerHeight", fmt(Double(NSTableHeaderView().frame.height)))])
    // A menu's own layout, read off NSMenu.size rather than a screenshot: one
    // item gives the chrome, each further item the row height.
    let menuFont = NSFont.menuFont(ofSize: 0)
    func sized(_ build: (NSMenu) -> Void) -> NSSize { let m = NSMenu(); build(m); return m.size }
    let one = sized { $0.addItem(withTitle: "Item 0", action: nil, keyEquivalent: "") }
    let two = sized { $0.addItem(withTitle: "Item 0", action: nil, keyEquivalent: "")
                      $0.addItem(withTitle: "Item 0", action: nil, keyEquivalent: "") }
    let sep = sized { $0.addItem(NSMenuItem.separator()) }
    let checked = sized { let i = NSMenuItem(title: "Item 0", action: nil, keyEquivalent: ""); i.state = .on; $0.addItem(i) }
    let indented = sized { let i = NSMenuItem(title: "Item 0", action: nil, keyEquivalent: ""); i.indentationLevel = 1; $0.addItem(i) }
    let titleWidth = ("Item 0" as NSString).size(withAttributes: [.font: menuFont]).width
    extra("menu", [("font", quote(menuFont.fontName)),
                   ("fontSize", fmt(Double(menuFont.pointSize))),
                   ("rowHeight", fmt(Double(two.height - one.height))),
                   ("chromeHeight", fmt(Double(one.height - (two.height - one.height)))),
                   ("separatorHeight", fmt(Double(sep.height - (one.height - (two.height - one.height))))),
                   ("widthOverText", fmt(Double(one.width) - Double(titleWidth.rounded(.up)))),
                   ("checkColumn", fmt(Double(checked.width - one.width))),
                   ("indentStep", fmt(Double(indented.width - one.width))),
                   ("width", fmt(Double(one.width))), ("height", fmt(Double(one.height)))])
    return "{\n  \"controls\": [\n" + rows.joined(separator: ",\n")
        + "\n  ],\n  \"extras\": [\n" + extras.joined(separator: ",\n") + "\n  ]\n}"
}

// ============================================================== 5. control shots
final class KeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
final class Board: NSView {
    /// AppKit composites a focus ring in its own layer, which an offscreen
    /// capture never sees. Drawing the control's own mask under the system ring
    /// style reproduces the real ring instead of imitating one.
    var focusTarget: NSView?
    override var isFlipped: Bool { false }
    override func draw(_ dirty: NSRect) {
        super.draw(dirty)
        guard let target = focusTarget, let context = NSGraphicsContext.current else { return }
        NSGraphicsContext.saveGraphicsState()
        context.cgContext.translateBy(x: target.frame.minX, y: target.frame.minY)
        NSFocusRingPlacement.only.set()
        target.drawFocusRingMask()
        NSGraphicsContext.restoreGraphicsState()
    }
}

enum ShotState: String, CaseIterable {
    case normal, checked, pressed, pressedChecked, disabled, disabledChecked, focused, inactive, inactiveChecked
    var on: Bool {
        self == .checked || self == .pressedChecked || self == .disabledChecked || self == .inactiveChecked
    }
    var needsKey: Bool { self != .inactive && self != .inactiveChecked }
}

let pad: CGFloat = 12
let fixedWidth: [String: CGFloat] = [
    "text_field": 160, "placeholder_field": 160, "secure_field": 160, "search_field": 160,
    "slider": 160, "progress_bar": 160, "level_indicator": 120, "combo_box": 160, "group_box": 160,
]
let shotControls = [
    "push_button", "default_button", "check_box", "mixed_check_box", "radio_button",
    "switch_control", "popup_button", "pulldown_button", "combo_box", "segmented",
    "text_field", "placeholder_field", "secure_field", "search_field",
    "stepper", "slider", "progress_bar", "level_indicator", "disclosure", "group_box",
]
let shotScales: [CGFloat] = [1, 2, 4]

/// Lets AppKit finish becoming key, resolve first responder and end animations.
func settle(_ seconds: CFTimeInterval = 0.06) {
    let deadline = CFAbsoluteTimeGetCurrent() + seconds
    repeat {
        CFRunLoopRunInMode(.defaultMode, 0.01, true)
    } while CFAbsoluteTimeGetCurrent() < deadline
}

/// sRGB, not calibratedRGB. Apple's generic RGB is gamma 1.8, so a capture taken
/// in it reports every colour several steps off what the renderer will emit.
func writePNG(_ view: NSView, _ appearance: NSAppearance, scale: CGFloat, path: String) {
    let bounds = view.bounds
    let px = Int((bounds.width * scale).rounded()), py = Int((bounds.height * scale).rounded())
    guard px > 0, py > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
          let cg = CGContext(data: nil, width: px, height: py, bitsPerComponent: 8,
                             bytesPerRow: px * 4, space: space,
                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
    cg.scaleBy(x: scale, y: scale)
    let ctx = NSGraphicsContext(cgContext: cg, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    appearance.performAsCurrentDrawingAppearance { view.displayIgnoringOpacity(bounds, in: ctx) }
    NSGraphicsContext.restoreGraphicsState()
    guard let image = cg.makeImage() else { return }
    let rep = NSBitmapImageRep(cgImage: image)
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
}

var shotRows: [String] = []

/// One key window reused for every shot. A fresh window per shot never becomes
/// key, and without a key window the default button, focus ring, switch fill and
/// active tint are all wrong. A second window stays non-key for the inactive row.
final class Stage {
    let key: KeyWindow
    let idle: NSWindow
    init() {
        let frame = NSRect(x: 80, y: 80, width: 320, height: 120)
        key = KeyWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        key.contentView = Board(frame: NSRect(origin: .zero, size: frame.size))
        idle = NSWindow(contentRect: NSRect(x: 460, y: 80, width: 320, height: 120),
                        styleMask: [.borderless], backing: .buffered, defer: false)
        idle.contentView = Board(frame: NSRect(origin: .zero, size: frame.size))
    }
    func start() {
        idle.orderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        key.makeKeyAndOrderFront(nil)
    }
    func window(for state: ShotState) -> NSWindow { state.needsKey ? key : idle }
}
let stage = Stage()

func capture(_ name: String, _ sizeName: String, _ cs: NSControl.ControlSize,
             _ state: ShotState, _ appearanceName: String, _ appearance: NSAppearance) {
    guard let control = makers(cs, on: state.on).first(where: { $0.0 == name })?.1 else { return }
    if let c = control as? NSControl { c.sizeToFit() } else { control.setFrameSize(control.fittingSize) }
    if let w = fixedWidth[name] { control.setFrameSize(NSSize(width: w, height: control.frame.height)) }
    if control.frame.width < 4 || control.frame.height < 4 {
        control.setFrameSize(NSSize(width: max(control.frame.width, 40), height: max(control.frame.height, 12)))
    }
    let boardSize = NSSize(width: (control.frame.width + pad * 2).rounded(),
                           height: (control.frame.height + pad * 2).rounded())
    let window = stage.window(for: state)
    window.appearance = appearance
    window.setContentSize(boardSize)
    let board = Board(frame: NSRect(origin: .zero, size: boardSize))
    board.wantsLayer = true
    appearance.performAsCurrentDrawingAppearance {
        board.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }
    window.contentView = board
    control.setFrameOrigin(NSPoint(x: pad, y: pad))
    board.addSubview(control)

    switch state {
    case .pressed, .pressedChecked: (control as? NSControl)?.isHighlighted = true
    case .disabled, .disabledChecked: (control as? NSControl)?.isEnabled = false
    case .focused:
        window.makeFirstResponder(control)
        board.focusTarget = control
    default: window.makeFirstResponder(nil)
    }
    board.layoutSubtreeIfNeeded()
    // AppKit resolves first responder and ends the switch animation on a later turn.
    settle()
    board.displayIfNeeded()

    for scale in shotScales {
        let file = "\(name)_\(sizeName)_\(state.rawValue)_\(appearanceName)@\(Int(scale))x.png"
        writePNG(board, appearance, scale: scale, path: outRoot + "/shots/" + file)
        shotRows.append("    " + obj([
            ("file", quote(file)), ("control", quote(name)), ("size", quote(sizeName)),
            ("state", quote(state.rawValue)), ("appearance", quote(appearanceName)),
            ("scale", fmt(Double(scale))), ("pad", fmt(Double(pad))),
            ("controlWidth", fmt(Double(control.frame.width))),
            ("controlHeight", fmt(Double(control.frame.height))),
            ("boardWidth", fmt(Double(boardSize.width))), ("boardHeight", fmt(Double(boardSize.height))),
        ]))
    }
}

// ============================================================== 6. the pinned run
func pinnedJSON() -> String {
    let os = ProcessInfo.processInfo.operatingSystemVersion
    var build = "unknown"
    if let raw = try? String(contentsOfFile: "/System/Library/CoreServices/SystemVersion.plist", encoding: .utf8),
       let key = raw.range(of: "ProductBuildVersion</key>") {
        let tail = raw[key.upperBound...]
        if let a = tail.range(of: "<string>"), let b = tail.range(of: "</string>") {
            build = String(tail[a.upperBound..<b.lowerBound])
        }
    }
    let w = NSWorkspace.shared
    return "{\n" + [
        ("product", quote("macOS")),
        ("version", quote("\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)")),
        ("build", quote(build)),
        ("accent", quote("multicolor (system default controlAccentColor)")),
        ("accentLight", inAppearance(aqua) { hex(NSColor.controlAccentColor) }),
        ("accentDark", inAppearance(darkAqua) { hex(NSColor.controlAccentColor) }),
        ("reduceMotion", w.accessibilityDisplayShouldReduceMotion ? "1" : "0"),
        ("reduceTransparency", w.accessibilityDisplayShouldReduceTransparency ? "1" : "0"),
        ("increaseContrast", w.accessibilityDisplayShouldIncreaseContrast ? "1" : "0"),
        ("differentiateWithoutColor", w.accessibilityDisplayShouldDifferentiateWithoutColor ? "1" : "0"),
        ("invertColors", w.accessibilityDisplayShouldInvertColors ? "1" : "0"),
        ("scrollerStyle", quote(NSScroller.preferredScrollerStyle == .overlay ? "overlay" : "legacy")),
        ("backingScaleFactor", fmt(Double(NSScreen.main?.backingScaleFactor ?? 0))),
        ("controlSizes", quote("mini, small, regular, large")),
        ("capture", quote("key NSWindow in an app bundle, displayIgnoringOpacity into an NSBitmapImageRep")),
    ].map { "  \(quote($0.0)): \($0.1)" }.joined(separator: ",\n") + "\n}"
}

func write(_ name: String, _ text: String) {
    try? text.write(toFile: outRoot + "/" + name, atomically: true, encoding: .utf8)
    print("wrote \(outRoot)/\(name)")
}

final class Delegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ note: Notification) {
        stage.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.run() }
    }
    func run() {
        write("pinned.json", pinnedJSON())
        write("colors.json", colourJSON())
        write("fonts.json", fontJSON())
        write("geometry.json", geometryJSON())
        for (sizeName, cs) in sizes {
            for name in shotControls {
                for state in ShotState.allCases {
                    for (appearanceName, appearance) in [("light", aqua), ("dark", darkAqua)] {
                        capture(name, sizeName, cs, state, appearanceName, appearance)
                    }
                }
            }
        }
        write("shots.json", "{\n  \"shots\": [\n" + shotRows.joined(separator: ",\n") + "\n  ]\n}")
        print("shots: \(shotRows.count)  keyWindow: \(stage.key.isKeyWindow)  active: \(NSApp.isActive)")
        if !stage.key.isKeyWindow || !NSApp.isActive {
            FileHandle.standardError.write(Data("reference capture lost key status; shots are not trustworthy\n".utf8))
            exit(2)
        }
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = Delegate()
app.delegate = delegate
app.run()
