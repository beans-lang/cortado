// Records what AppKit's own controls do *between* two states.
// Native code is allowed here; it never ships. Runs inside an app bundle so the
// window becomes key — an inactive window animates differently, or not at all.
import AppKit
import QuartzCore

let outRoot = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/motion"
try? FileManager.default.createDirectory(atPath: outRoot + "/frames", withIntermediateDirectories: true)

final class KeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

func fmt(_ v: Double) -> String {
    if v.isNaN || v.isInfinite { return "null" }
    return String(format: "%.4f", v)
}

/// Renders the *presentation* tree, not the model tree. A plain
/// `displayIgnoringOpacity` draws where the control is going; the presentation
/// layer is where it is right now, which is the only thing worth recording.
func snapshot(_ view: NSView, scale: CGFloat) -> NSBitmapImageRep? {
    let bounds = view.bounds
    let px = Int((bounds.width * scale).rounded()), py = Int((bounds.height * scale).rounded())
    guard px > 0, py > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
          let cg = CGContext(data: nil, width: px, height: py, bitsPerComponent: 8,
                             bytesPerRow: px * 4, space: space,
                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
          let layer = view.layer else { return nil }
    cg.scaleBy(x: scale, y: scale)
    (layer.presentation() ?? layer).render(in: cg)
    guard let image = cg.makeImage() else { return nil }
    return NSBitmapImageRep(cgImage: image)
}

/// The mean colour of the whole board. A fill that fades changes this while
/// nothing moves, which a centroid alone would record as "instant".
func signature(_ rep: NSBitmapImageRep) -> (Double, Double, Double) {
    var r = 0.0, g = 0.0, b = 0.0, n = 0.0
    var y = 0
    while y < rep.pixelsHigh {
        var x = 0
        while x < rep.pixelsWide {
            if let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) {
                r += Double(c.redComponent); g += Double(c.greenComponent); b += Double(c.blueComponent); n += 1
            }
            x += 2
        }
        y += 2
    }
    return n > 0 ? (r / n, g / n, b / n) : (0, 0, 0)
}

/// Where the moving part is, as a fraction of its travel: the mean x of every
/// pixel that differs from the row's background, weighted by how different.
func centroidX(_ rep: NSBitmapImageRep, _ background: NSColor) -> Double {
    guard let bg = background.usingColorSpace(.sRGB) else { return .nan }
    var sum = 0.0, weight = 0.0
    let y = rep.pixelsHigh / 2
    for x in 0..<rep.pixelsWide {
        guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
        let d = abs(c.redComponent - bg.redComponent) + abs(c.greenComponent - bg.greenComponent)
              + abs(c.blueComponent - bg.blueComponent)
        if d > 0.04 { sum += Double(x) * Double(d); weight += Double(d) }
    }
    return weight > 0 ? sum / weight : .nan
}

struct Scene {
    let name: String
    let view: NSView
    let apply: (Int) -> Void      // step 0 then step 1
    let steps: Int
}

let scale: CGFloat = 2
let frameSeconds = 1.0 / 120.0
let recordSeconds = 0.9

final class Recorder {
    /// One window per scene. Swapping the content view of a window that has
    /// already tracked a click leaves the next synthesized click unhandled.
    var window = KeyWindow(contentRect: NSRect(x: 60, y: 60, width: 240, height: 60),
                           styleMask: [.titled], backing: .buffered, defer: false)
    var rows: [String] = []

    func host(_ control: NSView, width: CGFloat, height: CGFloat) -> NSView {
        let board = NSView(frame: NSRect(x: 0, y: 0, width: width + 20, height: height + 20))
        board.wantsLayer = true
        board.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        control.setFrameOrigin(NSPoint(x: 10, y: 10))
        board.addSubview(control)
        return board
    }

    /// A real click, not `state = .on`. AppKit only animates a control that a
    /// person operated; a programmatic state change jumps, so recording one
    /// would say every macOS control is instant, which is false.
    func click(_ control: NSView, at point: NSPoint) {
        let inWindow = control.convert(point, to: nil)
        guard let down = NSEvent.mouseEvent(with: .leftMouseDown, location: inWindow,
                modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                clickCount: 1, pressure: 1),
              let up = NSEvent.mouseEvent(with: .leftMouseUp, location: inWindow,
                modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime + 0.03,
                windowNumber: window.windowNumber, context: nil, eventNumber: 1,
                clickCount: 1, pressure: 0) else { return }
        // The mouse-up has to be in the queue first: mouseDown runs its own
        // tracking loop and only returns once it reads one.
        NSApp.postEvent(up, atStart: false)
        NSApp.sendEvent(down)
    }

    func record(_ name: String, _ board: NSView, _ control: NSView,
                hit: NSPoint? = nil, apply: @escaping (Int) -> Void) {
        window.orderOut(nil)
        window = KeyWindow(contentRect: NSRect(x: 60, y: 60, width: board.frame.width, height: board.frame.height),
                           styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = board
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        pump(0.15)
        apply(0)
        board.layoutSubtreeIfNeeded(); board.displayIfNeeded()
        pump(0.3)
        let before = snapshot(board, scale: scale)
        var samples: [(Double, Double)] = []
        var colours: [(Double, Double, Double)] = []
        let background = NSColor.windowBackgroundColor
        if let point = hit { click(control, at: point) } else { apply(1) }
        let start = CACurrentMediaTime()
        var index = 0
        while CACurrentMediaTime() - start < recordSeconds {
            let t = CACurrentMediaTime() - start
            if let rep = snapshot(board, scale: scale) {
                samples.append((t, centroidX(rep, background)))
                colours.append(signature(rep))
                if index % 4 == 0 {
                    let file = "\(name)_\(String(format: "%03d", index)).png"
                    try? rep.representation(using: .png, properties: [:])?
                        .write(to: URL(fileURLWithPath: outRoot + "/frames/" + file))
                }
            }
            index += 1
            pump(frameSeconds)
        }
        _ = before
        let points = samples.filter { !$0.1.isNaN }
        guard let first = points.first?.1, let last = points.last?.1 else { return }
        let span = last - first
        // Colour progress: how far this frame's mean colour has travelled from
        // the first frame's towards the last one's.
        let c0 = colours.first ?? (0, 0, 0), c1 = colours.last ?? (0, 0, 0)
        let dr = c1.0 - c0.0, dg = c1.1 - c0.1, db = c1.2 - c0.2
        let norm = dr * dr + dg * dg + db * db
        func colourAt(_ i: Int) -> Double {
            guard norm > 1e-9, i < colours.count else { return 0 }
            let c = colours[i]
            return ((c.0 - c0.0) * dr + (c.1 - c0.1) * dg + (c.2 - c0.2) * db) / norm
        }
        let moves = abs(span) > 0.5
        let fades = norm > 4e-6
        var settled = recordSeconds
        if moves || fades {
            for (i, (t, x)) in points.enumerated() {
                let near = (!moves || abs(x - last) <= abs(span) * 0.02)
                    && (!fades || abs(colourAt(i) - 1.0) <= 0.02)
                if near { settled = min(settled, t) }
            }
        } else { settled = 0 }
        var series: [String] = []
        for (i, (t, x)) in points.enumerated() {
            let progress = moves ? (x - first) / span : 0
            series.append("      {\"t\": \(fmt(t)), \"x\": \(fmt(x / Double(scale))), "
                          + "\"p\": \(fmt(progress)), \"c\": \(fmt(colourAt(i)))}")
        }
        rows.append("    {\n      \"scene\": \"\(name)\",\n      \"moved\": \(fmt(span / Double(scale))),\n"
                    + "      \"fade\": \(fmt(norm > 0 ? norm.squareRoot() : 0)),\n"
                    + "      \"settled\": \(fmt(settled)),\n      \"samples\": [\n"
                    + series.joined(separator: ",\n") + "\n      ]\n    }")
        print("\(name): moved \(span / Double(scale))pt, fade \(norm.squareRoot()), settled \(settled)s, \(points.count) samples")
    }

    func pump(_ seconds: CFTimeInterval) {
        let deadline = CFAbsoluteTimeGetCurrent() + seconds
        repeat { CFRunLoopRunInMode(.defaultMode, 0.001, true) } while CFAbsoluteTimeGetCurrent() < deadline
    }
}

final class Delegate: NSObject, NSApplicationDelegate {
    let rec = Recorder()
    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.run() }
    }
    func run() {
        let sw = NSSwitch(); sw.sizeToFit()
        rec.record("switch_on", rec.host(sw, width: sw.frame.width, height: sw.frame.height), sw,
                   hit: NSPoint(x: sw.frame.width / 2, y: sw.frame.height / 2)) { step in
            sw.state = step == 0 ? .off : .on
        }
        let sw2 = NSSwitch(); sw2.sizeToFit()
        rec.record("switch_off", rec.host(sw2, width: sw2.frame.width, height: sw2.frame.height), sw2,
                   hit: NSPoint(x: sw2.frame.width / 2, y: sw2.frame.height / 2)) { step in
            if step == 0 { sw2.state = .on }
        }
        let seg = NSSegmentedControl(labels: ["One", "Two", "Three"], trackingMode: .selectOne, target: nil, action: nil)
        seg.sizeToFit(); seg.selectedSegment = 0
        rec.record("segmented", rec.host(seg, width: seg.frame.width, height: seg.frame.height), seg,
                   hit: NSPoint(x: seg.frame.width * 5 / 6, y: seg.frame.height / 2)) { step in
            if step == 0 { seg.selectedSegment = 0 }
        }
        let slider = NSSlider(value: 0.1, minValue: 0, maxValue: 1, target: nil, action: nil)
        slider.setFrameSize(NSSize(width: 160, height: slider.frame.height))
        rec.record("slider_jump", rec.host(slider, width: 160, height: slider.frame.height), slider,
                   hit: NSPoint(x: 140, y: slider.frame.height / 2)) { step in
            if step == 0 { slider.doubleValue = 0.1 }
        }
        let slider2 = NSSlider(value: 0.1, minValue: 0, maxValue: 1, target: nil, action: nil)
        slider2.setFrameSize(NSSize(width: 160, height: slider2.frame.height))
        rec.record("slider_set", rec.host(slider2, width: 160, height: slider2.frame.height), slider2) { step in
            slider2.doubleValue = step == 0 ? 0.1 : 0.9
        }
        let tabView = NSTabView(frame: NSRect(x: 0, y: 0, width: 220, height: 120))
        let a = NSTabViewItem(identifier: "a"); a.label = "Alpha"
        let b = NSTabViewItem(identifier: "b"); b.label = "Beta"
        tabView.addTabViewItem(a); tabView.addTabViewItem(b)
        rec.record("tab_view", rec.host(tabView, width: 220, height: 120), tabView,
                   hit: NSPoint(x: 128, y: 111)) { step in
            if step == 0 { tabView.selectTabViewItem(at: 0) }
        }
        let push = NSButton(title: "Button", target: nil, action: nil); push.bezelStyle = .push
        push.sizeToFit()
        rec.record("button_press", rec.host(push, width: push.frame.width, height: push.frame.height), push) { step in
            push.isHighlighted = step == 1
        }
        let check = NSButton(checkboxWithTitle: "Check", target: nil, action: nil); check.sizeToFit()
        rec.record("check_on", rec.host(check, width: check.frame.width, height: check.frame.height), check,
                   hit: NSPoint(x: 8, y: check.frame.height / 2)) { step in
            if step == 0 { check.state = .off }
        }
        let text = "{\n  \"scenes\": [\n" + rec.rows.joined(separator: ",\n") + "\n  ]\n}"
        try? text.write(toFile: outRoot + "/motion.json", atomically: true, encoding: .utf8)
        print("wrote \(outRoot)/motion.json")
        NSApp.terminate(nil)
    }
}
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let d = Delegate(); app.delegate = d; app.run()
