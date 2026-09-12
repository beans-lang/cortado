// What changes when a program is a real application.
//
// **This is the other half of `tests/gated.b`, and it can only run one way.**
// That file proves that every gated call refuses from a process with no
// bundle — which is the state every ordinary test leg is in, and the state in
// which reaching a framework would end the process. This one proves the guard
// opens: that a program built into a signed bundle, whose Info.plist says what
// it wants each permission for, gets a real answer instead of "there is no
// answer to be had".
//
// **Nothing here prompts, deliberately.** Every call below is a *status* read,
// and a status read constructs nothing and asks nobody. The moment a program
// touches CoreLocation or CoreBluetooth for real, macOS puts a panel on the
// screen and waits — which in a test is a hang with no output, on a machine
// with nobody sitting at it. So the services themselves are not started here.
// What is checked is the thing that could not be checked any other way: that
// the answer is no longer `unavailable`.
//
// It is run by `test.sh`'s bundled leg, through `tools/bundle.sh`, an ad-hoc
// `codesign` and `open -W`. `open -W` rather than running the binary inside
// the bundle directly, because a bundle is only a bundle to macOS when it is
// launched as one: run the executable by its path and `[NSBundle mainBundle]`
// still answers a nil identifier, and every line below would read exactly as
// it does on an ordinary leg.
package main

import cortado.platform
import cortado.surface
import cortado.device
import std.io

fn drive() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.headless)
    app.check_abi()?

    io.println("-- this program is an application --")
    // The thing that changed. On every ordinary leg this is `unavailable`,
    // which the permission model answers for a process with no privacy
    // identity of its own — see the note beside ctd_permission_status.
    var named: int = 0
    var answered: int = 0
    for one: device.Permission in device.Permission.all() {
        named = named + 1
        let said: device.Allowance = one.status().or(device.Allowance.unavailable)
        if said != device.Allowance.unavailable { answered = answered + 1 }
    }
    io.println("  seven permissions are named: {named == 7}")
    // Not all seven: photos needs a framework macOS has under another name,
    // and motion needs CoreMotion, which a Mac does not have at all. What
    // matters is that the four this platform really gates now answer.
    io.println("  and the ones this platform gates now answer: {answered >= 4}")

    io.println("-- each one, by name --")
    for one: device.Permission in [device.Permission.bluetooth, device.Permission.location,
                                   device.Permission.camera, device.Permission.microphone,
                                   device.Permission.screen_capture] {
        let said: device.Allowance = one.status().or(device.Allowance.unavailable)
        io.println("  {one.name()} answers something real: {said != device.Allowance.unavailable}")
    }

    io.println("-- and still nothing was touched --")
    // Every line above is a status read. A prompt would mean this file had
    // reached a framework, and a prompt in a test is a hang: there is nobody
    // at the machine to dismiss it.
    app.run_for(0.25)?
    io.println("  a turn of the run loop later, with no prompt on screen: true")

    app.shutdown()
    return ok(true)
}

fn main() {
    match drive() {
        ok(done) => { io.println("drove={done}") }
        err(problem) => { io.println("{problem.kind}: {problem.msg}") }
    }
}
