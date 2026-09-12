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

    // ------------------------------------------- inside the border, not over it
    //
    // The one thing in this suite that catches a container drawing its
    // children in the wrong place, and the reason it has to be a picture.
    //
    // A group box's children live in a content view the platform positions
    // inside the border. A child's frame is read in *that view's* coordinates,
    // so it is (0, 0) whether the content view is where it should be or
    // twenty-two points too tall — which is what AppKit gave a box built at
    // zero size, for as long as cortado built them that way. The children of
    // every group box were drawn over the title and out of the top of the box,
    // and every golden in this suite stayed green through it, because a frame
    // read in the content view's own coordinates was right either way.
    //
    // What is compared is two pictures of the same button: one in a plain
    // container at a known offset, one at the corner of a group box. The ink a
    // control lays down is not its frame — AppKit's push-button bezel bleeds a
    // point or two outside it — so neither number means anything on its own,
    // and the difference between them is exactly the inset the box reported.
    if widgets.WidgetKind.group_box.available() {
        let offset: f64 = 8.0

        var plain: widgets.Container = new widgets.Container()
        box.add(plain)?
        plain.set_frame(geometry.Rect.of(0.0, 0.0, 100.0, 40.0))?
        let plain_bare: widgets.Snapshot = plain.snapshot()?
        var loose: widgets.Button = widgets.Button.of("Buy")?
        plain.add(loose)?
        loose.set_frame(geometry.Rect.of(0.0, offset, 40.0, 20.0))?
        let plain_ink: int = first_row(plain.snapshot()?, plain_bare)?

        var frame: widgets.GroupBox = widgets.GroupBox.of("Options")?
        box.add(frame)?
        frame.set_frame(geometry.Rect.of(0.0, 0.0, 100.0, 40.0))?
        let chrome: geometry.EdgeInsets = frame.content_inset()?
        let frame_bare: widgets.Snapshot = frame.snapshot()?
        var corner: widgets.Button = widgets.Button.of("Buy")?
        frame.add(corner)?
        corner.set_frame(geometry.Rect.of(0.0, 0.0, 40.0, 20.0))?
        let frame_ink: int = first_row(frame.snapshot()?, frame_bare)?

        io.println("a group box keeps room for its title: {chrome.top > chrome.bottom}")
        io.println("a child at its corner changes pixels: {frame_ink >= 0}")
        io.println("and starts exactly the title's height down: {frame_ink - plain_ink == (chrome.top - offset) as int}")
    }

    app.shutdown()
    return ok(true)
}

/// The first row of the picture that `filled` changed, or -1 for none.
///
/// Rows rather than columns, because the mistake this is here for is vertical:
/// a box's title band is at the top, and a content view that is too tall puts
/// its children above the title and out of the box, where the snapshot clips
/// them. The sides came out right even when that was broken.
fn first_row(filled: widgets.Snapshot, bare: widgets.Snapshot) -> Result<int> {
    var row: int = 0
    for row in 0..filled.height {
        var column: int = 0
        for column in 0..filled.width {
            if !filled.pixel(column, row)?.same_as(bare.pixel(column, row)?) {
                return ok(row)
            }
        }
    }
    return ok(-1)
}

fn main() {
    match build() {
        ok(done) => {}
        err(problem) => { io.println("{problem.kind}: {problem.msg}") }
    }
}
