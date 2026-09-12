// What the system says this program may do, and what it says when it cannot say.
//
// **This golden is the same bytes on every host, and on this one it is the
// same bytes whether the machine has granted anything or not.** That is not a
// weakness of the test; it is the contract. A program run from a build
// directory has no bundle, so it has no privacy identity — the system answers
// for whatever process is responsible for it, which is a terminal — and
// cortado says `unavailable` rather than passing that number on. A probe read
// "microphone: authorized" from a program with no usage description at all,
// because Terminal.app holds that grant, and reporting it would have been
// worse than reporting nothing.
//
// So what this file checks is the shape of the contract, which holds
// everywhere:
//
//   * every permission answers one of exactly four things;
//   * a number that is not a permission is refused rather than answered;
//   * asking outside a bundle is refused rather than prompting — which is the
//     line that matters, because prompting without a usage description is what
//     ends the process;
//   * and the answer here is `unavailable`, for every permission, because
//     nothing that runs this file is bundled.
//
// The other side — a real grant, a real prompt — needs a signed bundle, and
// `tools/bundle.sh` is how one is made. It is not part of this gate: a case
// that showed a prompt would need somebody to click it.
package main

import cortado.platform
import cortado.surface
import cortado.device
import std.io

fn drive() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.headless)
    app.check_abi()?

    let every: List<device.Permission> = device.Permission.all()
    var asked: int = 0
    var answered_one_of_four: int = 0
    var unavailable_here: int = 0
    var request_refused: int = 0

    for what: device.Permission in every {
        asked = asked + 1
        match what.status() {
            ok(answer) => {
                // Four words and no others. The enum makes that true by
                // construction, so what is really being checked is that the
                // host answered a number the enum has a word for — an unknown
                // one becomes `unavailable`, which is the safe reading.
                answered_one_of_four = answered_one_of_four + 1
                if answer == device.Allowance.unavailable {
                    unavailable_here = unavailable_here + 1
                } else {
                    io.println("  ...{what.name()} answered {answer.name()}")
                }
            }
            err(problem) => {
                io.println("  ...{what.name()} refused: {problem.kind}")
            }
        }

        // The line that matters. Asking without a bundle and without a usage
        // description is what ends the process on macOS, so it has to be
        // refused *before* anything is touched — and this case runs exactly
        // that path on every host.
        match what.request(7) {
            ok(asking) => { io.println("  ...{what.name()} started a prompt from an unbundled process") }
            err(problem) => {
                if problem.kind == "unsupported" { request_refused = request_refused + 1 }
                else { io.println("  ...{what.name()} refused a request with {problem.kind}") }
            }
        }
    }

    io.println("-- the shape of the contract --")
    io.println("  cortado names this many permissions: {every.len()}")
    io.println("  every one of them was asked: {asked == every.len()}")
    io.println("  and answered one of the four words: {answered_one_of_four == asked}")

    io.println("-- outside a bundle --")
    io.println("  every one answers that there is no answer to be had: {unavailable_here == asked}")
    io.println("  and asking is refused rather than prompting: {request_refused == asked}")

    io.println("-- the four words --")
    io.println("  there are this many: {device.Allowance.all().len()}")
    io.println("  and a number the host has no word for reads as unavailable: {device.Allowance.of(99) == device.Allowance.unavailable}")

    app.shutdown()
    return ok(true)
}

fn main() {
    match drive() {
        ok(done) => { io.println("drove={done}") }
        err(problem) => { io.println("{problem.kind}: {problem.msg}") }
    }
}
