// The four services the operating system will not let a program have for free,
// and the one thing this file exists to prove about them.
//
// **Every call here can end the process.** macOS does not refuse a program
// that reaches a privacy-gated framework without the matching usage
// description in its Info.plist — it terminates it, on a *later* turn of the
// run loop, in unrelated code, with nothing on stderr and no status anybody
// could turn into an error. There is no process left to return one.
//
// So this file is not a test of what Bluetooth does. It is a test of the
// guard: **every one of these, called from a process with no bundle, refuses —
// and the program is still running afterwards to say so.** That last clause is
// the whole assertion. A host that forgot the guard would not fail a line
// here; it would take the suite down somewhere else entirely, with a stack
// about whatever was running at the time.
//
// It runs on the ordinary legs, and it has to: the failure it is looking for
// is *not being bundled*, which is exactly the state an ordinary leg is in.
// The bundled half — that these work when a program is a real application — is
// `tools/bundle.sh` and the leg that drives it, which is the only place a
// prompt can appear at all.
//
// Cross-host, and in the agreement shape. Two platforms have all four
// services, one has three, and one has none; what every host agrees on is that
// asking without the right to ask is answered rather than fatal.
package main

import cortado.platform
import cortado.surface
import cortado.device
import cortado.events
import cortado.host
import std.io

/// Whether a call was refused the way it should be.
///
/// `unsupported` is the answer the guard gives, and `wrong_moment` is what a
/// service that *is* allowed gives before it has anything to say. Both are
/// refusals; neither is a crash, which is the only outcome this file is
/// really checking against.
fn refused(kind: string) -> bool {
    return kind == "unsupported" || kind == "wrong_moment" || kind == "out_of_range"
}

fn refused_bool(answer: Result<bool>) -> bool {
    match answer {
        ok(done) => { return false }
        err(problem) => { return refused(problem.kind) }
    }
}

fn refused_text(answer: Result<string>) -> bool {
    match answer {
        ok(said) => { return false }
        err(problem) => { return refused(problem.kind) }
    }
}

fn refused_real(answer: Result<f64>) -> bool {
    match answer {
        ok(value) => { return false }
        err(problem) => { return refused(problem.kind) }
    }
}

fn refused_int(answer: Result<int>) -> bool {
    match answer {
        ok(value) => { return false }
        err(problem) => { return refused(problem.kind) }
    }
}

fn drive() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.headless)
    app.check_abi()?

    io.println("-- what this platform claims --")
    // The capability and the permission are two ways of asking one question
    // and must not disagree: a program that laid out a screen from one and
    // called the other would build a panel for a service it cannot use.
    let has_place: bool = device.Gated.knows_place()
    let has_nearby: bool = device.Gated.knows_nearby()
    let has_capture: bool = device.Gated.knows_capture()
    let has_screen: bool = device.Gated.knows_screen()
    io.println("  four services, each claimed or not: {has_place == platform.Capability.location.available() && has_nearby == platform.Capability.bluetooth.available() && has_capture == platform.Capability.capture.available() && has_screen == platform.Capability.screen.available()}")

    io.println("-- nobody here is a bundle --")
    // This is the state an ordinary test leg is in, and the state every
    // gated call must survive. `beansc run` is worse still: the process is
    // `beansc`, whose grants belong to whoever installed it.
    let unbundled: bool = device.Permission.bluetooth.status().or(device.Allowance.granted) == device.Allowance.unavailable
    io.println("  and the permission model says so: {unbundled}")

    io.println("-- where the machine is --")
    io.println("  starting is refused: {refused_bool(device.Gated.watch_place())}")
    // Stopping something that never started is harmless on every host — it is
    // the one call in this section that does not touch a framework even where
    // it is allowed to, because there is nothing to stop.
    var stop_ok: bool = false
    match device.Gated.stop_place() {
        ok(done) => { stop_ok = true }
        err(problem) => { stop_ok = refused(problem.kind) }
    }
    io.println("  stopping what never started is harmless: {stop_ok}")
    var place_refused: bool = false
    match device.Gated.where_now() {
        ok(here) => { place_refused = false }
        err(problem) => { place_refused = refused(problem.kind) }
    }
    io.println("  and asking where is refused: {place_refused}")

    io.println("-- what is nearby --")
    io.println("  scanning is refused: {refused_bool(device.Gated.scan(true))}")
    io.println("  and nothing was seen: {device.Gated.nearby_count() == 0}")
    io.println("  a row that cannot exist has no name: {refused_text(device.Gated.nearby_name(0))}")
    io.println("  and no identifier: {refused_text(device.Gated.nearby_id(0))}")
    io.println("  and no signal: {refused_real(device.Gated.nearby_signal(0))}")
    io.println("  connecting to it is refused: {refused_bool(device.Gated.connect(0, true))}")
    io.println("  and it is not connected: {!device.Gated.connected(0)}")

    io.println("-- what it can see and hear --")
    let cameras: int = device.Gated.capture_count(device.CaptureKind.camera)
    let microphones: int = device.Gated.capture_count(device.CaptureKind.microphone)
    io.println("  nothing is enumerated: {cameras == 0 && microphones == 0}")
    io.println("  and naming one is refused: {refused_text(device.Gated.capture_name(device.CaptureKind.camera, 0))}")
    io.println("  and none is the default: {!device.Gated.capture_is_default(device.CaptureKind.microphone, 0)}")

    io.println("-- what is on the screen --")
    io.println("  no display can be recorded: {device.Gated.screen_count() == 0}")
    var size_refused: bool = false
    match device.Gated.screen_size(0) {
        ok(size) => { size_refused = false }
        err(problem) => { size_refused = refused(problem.kind) }
    }
    io.println("  measuring one is refused: {size_refused}")
    io.println("  asking for a frame is refused: {refused_bool(device.Gated.capture_screen(0, 7))}")
    io.println("  and taking one nobody asked for is refused: {refused_int(device.Gated.take_frame(7))}")

    io.println("-- and the program is still here --")
    // The line the whole file is written for. A guard that let one call
    // through would not fail a line above — the process would be gone, and
    // this would never print.
    //
    // A turn of the loop first, because that is where a privacy death lands:
    // not in the call that caused it, but on the next turn, in whatever was
    // running then. Nineteen calls have been made above; if any of them
    // touched a framework it had no right to, this is where the process ends.
    app.run_for(0.25)?
    io.println("  nineteen gated calls later, after a turn of the run loop: true")

    app.shutdown()
    return ok(true)
}

fn main() {
    match drive() {
        ok(done) => { io.println("drove={done}") }
        err(problem) => { io.println("{problem.kind}: {problem.msg}") }
    }
}
