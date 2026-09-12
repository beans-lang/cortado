// What this program is allowed to do, and what it does about "no answer".
//
//     beansc build examples/permissions.b -o build/permissions
//     ./build/permissions                      # every answer is "unavailable"
//
//     tools/bundle.sh build/permissions Permissions \
//         org.beans-lang.cortado.permissions '' \
//         NSCameraUsageDescription='to scan a receipt'
//     codesign --force --sign - build/Permissions.app
//     open -W --stdout /dev/stdout build/Permissions.app
//
// Run it the first way and every permission answers `unavailable`. That is not
// a bug and it is not cortado being cautious: a program with no bundle has no
// privacy identity, and macOS answers for whichever process is *responsible*
// for it — a terminal, usually. A probe read "microphone: authorized" from a
// program with no usage description at all, because Terminal.app holds that
// grant. Passing that number on would have been worse than passing nothing.
//
// Run it the second way and the camera answers for real, because the bundle
// has a name, a signature and the sentence macOS shows in the prompt.
//
// **The refusal is the feature.** Asking for a permission the Info.plist does
// not declare does not fail on macOS — it *ends the process*, on a later turn
// of the run loop, in unrelated code, with nothing on stderr. cortado refuses
// before touching anything, so the worst that happens is a message.
package main

import cortado.platform
import cortado.surface
import cortado.device
import cortado.host
import cortado.events
import std.io

fn run() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.headless)
    app.check_abi()?

    io.println("what this program may do:")
    var anything_to_ask: bool = false
    for what: device.Permission in device.Permission.all() {
        let answer: device.Allowance = what.status()?
        io.println("  {what.name()}: {answer.name()}")
        if answer == device.Allowance.undecided { anything_to_ask = true }
    }

    if !anything_to_ask {
        io.println("")
        // Two different reasons for the same silence, and a program that
        // conflated them would tell the user the wrong thing: nothing left to
        // ask because it was all asked already, or nothing *askable* because
        // this process has no privacy identity at all.
        var any_real_answer: bool = false
        for what: device.Permission in device.Permission.all() {
            if what.status()? != device.Allowance.unavailable { any_real_answer = true }
        }
        if any_real_answer {
            io.println("nothing left to ask: every permission this program")
            io.println("declares has already been answered.")
        } else {
            io.println("nothing to ask about. Unbundled, every answer is")
            io.println("\"unavailable\" — see the note at the top of this file.")
        }
        app.shutdown()
        return ok(true)
    }

    // One handler for every request: the token says which one answered, which
    // is why a request takes one.
    // A permission answer belongs to the program, not to a control, so it is
    // registered against no handle — the same way `post` and a dialog's answer
    // are.
    app.router.on(host.Handle.none(), events.EventKind.permission,
        fn(event: events.UiEvent) {
            io.println("asked about {event.token}, answered {device.Allowance.of(event.index).name()}")
            app.stop()
        })

    match device.Permission.camera.request(1) {
        ok(asking) => {
            io.println("")
            io.println("asking about the camera...")
            app.run_for(30.0)?
        }
        err(problem) => {
            io.println("")
            io.println("cannot ask: {problem.msg}")
        }
    }

    app.shutdown()
    return ok(true)
}

fn main() {
    match run() {
        ok(done) => {}
        err(problem) => { io.println("{problem.kind}: {problem.msg}") }
    }
}
