// What survives the trip across the C boundary, and what is refused.
//
// Every string an application shows goes out through `ctd_set_text` as UTF-8
// with an explicit byte count and comes back through `ctd_get_text` with the
// two-call shape. Three things about that trip are easy to get wrong and
// impossible to notice from a test that only ever sends "Order a coffee":
//
//   * **Astral characters.** An emoji is four UTF-8 bytes and one Unicode
//     scalar, and on the platforms whose native string is UTF-16 it is two
//     code units. A host that measures in the wrong one truncates it in half
//     and produces a lone surrogate, which is not text at all.
//
//   * **Combining marks.** "e" followed by U+0301 is two scalars that render
//     as one character. A host that normalised — and several platform APIs
//     do, quietly — would hand back a string that is equal on screen and
//     different in bytes, and a program comparing what it wrote with what it
//     read would disagree with itself.
//
//   * **An embedded NUL.** This one is the reason the ABI takes a length
//     instead of a terminator, so it is the one that has to be pinned down.
//
// The golden below is the answer, and it is the same on every platform: text
// is where the hosts are most likely to drift, so this file is deliberately
// one of the portable ones.
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.geometry
import std.io

/// The byte count, said in the one unit the ABI uses. `string.len()` is not
/// necessarily it, and a test about bytes should not leave that to chance.
fn bytes_of(text: string) -> int {
    return Bytes.from(text).len()
}

/// Writes `text` into a control, reads it back off the live platform object,
/// and says whether the bytes made the round trip.
fn round_trip(name: string, control: widgets.Widget, text: string) {
    match control.set_display_text(text) {
        ok(_) => {}
        err(refused) => {
            io.println("{name}: refused ({refused.kind})")
            return
        }
    }
    match control.display_text() {
        ok(back) => {
            let sent: int = bytes_of(text)
            let got: int = bytes_of(back)
            if back == text {
                io.println("{name}: {sent} bytes, same")
            } else {
                io.println("{name}: {sent} bytes out, {got} bytes back, DIFFERENT")
            }
        }
        err(problem) => { io.println("{name}: unreadable ({problem.kind})") }
    }
}

fn build() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.headless)
    app.check_abi()?
    var window: surface.Window = app.window(300.0, 200.0, "Text")?
    var root: widgets.Container = new widgets.Container()
    window.set_root(root)?

    var label: widgets.Label = widgets.Label.of("")?
    var field: widgets.TextField = widgets.TextField.of("")?
    var area: widgets.TextArea = widgets.TextArea.of("")?
    var button: widgets.Button = widgets.Button.of("")?
    root.add(label)?
    root.add(field)?
    root.add(area)?
    root.add(button)?

    // Four bytes, one scalar, two UTF-16 code units.
    let emoji: string = "\u{1f600} good"
    // Two scalars that render as one character, and the same character
    // precomposed. They must stay different: a host that normalised would
    // make them equal and lose what the program wrote.
    let decomposed: string = "cafe\u{301}"
    let precomposed: string = "caf\u{e9}"
    // Right-to-left, and a script outside the Basic Multilingual Plane's
    // Latin comfort zone.
    let mixed: string = "\u{0645}\u{0631}\u{062d}\u{628}\u{627} \u{4f60}\u{597d}"

    round_trip("label emoji", label, emoji)
    round_trip("field emoji", field, emoji)
    round_trip("area emoji", area, emoji)
    round_trip("button emoji", button, emoji)
    round_trip("label decomposed", label, decomposed)
    round_trip("label precomposed", label, precomposed)
    round_trip("field mixed", field, mixed)

    io.println("decomposed and precomposed differ: {decomposed != precomposed}")
    io.println("decomposed bytes: {bytes_of(decomposed)}")
    io.println("precomposed bytes: {bytes_of(precomposed)}")

    // The embedded NUL. A platform text control cannot hold one — NSString's
    // UTF8String, GTK's const char* and Win32's SetWindowTextW all end at the
    // first zero byte — so cortado refuses it by name rather than letting a
    // string be silently cut in half somewhere inside the platform.
    let split: string = "before\u{0}after"
    io.println("nul string bytes: {bytes_of(split)}")
    round_trip("label nul", label, split)

    // **And the size that text implies changes with it.**
    //
    // A host is free to remember how big a control said it wanted to be —
    // asking is expensive on one of the four, where it was 78% of a layout
    // solve — and the macOS host does. What it must not do is remember it
    // across a write: a label given a longer word is wider, and one that laid
    // out at its old width would clip its own text for ever.
    //
    // There is nothing platform-specific to assert here. Every host has real
    // text metrics, so on every one of them more words is more width — and
    // this is the line that fails if an invalidation is ever dropped, which
    // until it was written nothing did.
    var ruler: widgets.Label = widgets.Label.of("i")?
    let narrow: geometry.Size = ruler.measure(geometry.Size.unbounded())?
    ruler.set_text("a much longer piece of text than the one before it")?
    let wide: geometry.Size = ruler.measure(geometry.Size.unbounded())?
    io.println("more words is more width: {wide.width > narrow.width}")
    // And back the other way, so the line above cannot pass on a host that
    // only ever grows its answer.
    ruler.set_text("i")?
    let narrow_again: geometry.Size = ruler.measure(geometry.Size.unbounded())?
    io.println("and fewer is fewer again: {narrow_again.width == narrow.width}")

    app.shutdown()
    return ok(true)
}

fn main() {
    match build() {
        ok(done) => {}
        err(problem) => { io.println("{problem.kind}: {problem.msg}") }
    }
}
