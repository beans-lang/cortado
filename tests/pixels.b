// Did anything actually get drawn?
//
// Every other test in this suite reads back a property the program itself set.
// A host that stored each value in a dictionary and never spoke to the
// platform at all would pass all of them: it would report the right text, the
// right frame, the right enabled state and the right child order, because
// those are the numbers it was handed. This is the one test that asks a
// question cortado does not already know the answer to.
//
// **It is not a golden, and that is deliberate.** Goldening pixels means
// goldening a font rasterizer and a theme, both of which change on an OS point
// release, and a suite that gets re-recorded every few months stops being read.
// What is asserted here is the set of facts that hold across releases and
// across themes:
//
//   * an image is the size that was asked for, and exactly four bytes a pixel;
//   * an empty box is one colour all over;
//   * a box with a real control in it is not;
//   * hiding that control puts the image back exactly as it was.
//
// The last one is the negative control. Without it, a snapshot that always
// returned the same blank bitmap would satisfy the first two, and "uniform"
// would be measuring nothing.
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.geometry
import std.io

fn build() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.headless)
    app.check_abi()?

    if !platform.Capability.snapshot.available() {
        // Said out loud rather than passed over. A platform that cannot read a
        // widget back is a platform where this claim is untested, and a run
        // that printed nothing would look the same as one that checked.
        io.println("snapshot: unsupported on this platform")
        app.shutdown()
        return ok(true)
    }

    var window: surface.Window = app.window(200.0, 120.0, "Pixels")?
    var box: widgets.Container = new widgets.Container()
    window.set_root(box)?
    box.set_frame(geometry.Rect.of(0.0, 0.0, 100.0, 40.0))?

    let empty: widgets.Snapshot = box.snapshot()?
    io.println("size: {empty.width}x{empty.height}, {empty.byte_count()} bytes")
    io.println("four bytes a pixel: {empty.byte_count() == empty.width * empty.height * 4}")
    io.println("empty box is one colour: {empty.is_uniform()?}")

    var press: widgets.Button = widgets.Button.of("Buy")?
    box.add(press)?
    press.set_frame(geometry.Rect.of(10.0, 6.0, 80.0, 28.0))?

    let painted: widgets.Snapshot = box.snapshot()?
    io.println("with a button, one colour: {painted.is_uniform()?}")
    io.println("the button changed pixels: {painted.differences(empty)? > 0}")

    // The negative control: take the control away and the image has to come
    // back exactly. A snapshot that answered the same blank bitmap every time
    // would pass everything above and fail this.
    press.set_hidden(true)?
    let hidden: widgets.Snapshot = box.snapshot()?
    io.println("hiding it restores the image: {hidden.differences(empty)? == 0}")

    // A zero-sized control paints nothing, and says so rather than answering
    // an empty image that a caller would read as "drawn, and blank".
    var thin: widgets.Label = widgets.Label.of("")?
    box.add(thin)?
    thin.set_frame(geometry.Rect.of(0.0, 0.0, 0.0, 0.0))?
    match thin.snapshot() {
        ok(nothing) => { io.println("a zero-sized control: answered {nothing.byte_count()} bytes") }
        err(refused) => { io.println("a zero-sized control: refused ({refused.kind})") }
    }

    app.shutdown()
    return ok(true)
}

fn main() {
    match build() {
        ok(done) => {}
        err(problem) => { io.println("{problem.kind}: {problem.msg}") }
    }
}
