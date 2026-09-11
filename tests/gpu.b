// What a platform promises about drawing on the GPU, and what it refuses.
//
// **This golden is the same bytes on a machine with a GPU host and on one
// without, and that is the point of how it is written.** Every line asks
// whether what happened *agrees with what the capability promised*, rather
// than printing what happened. A host with Metal opens a device, reads its
// name and three limits, and closes it; a host with none refuses all four. Two
// different sets of code run and the same line comes out, because the claim
// being made is not "there is a GPU" — it is "cortado tells you the truth
// about whether there is one, and never quietly does nothing".
//
// The alternative was the shape `tests/pixels.b` uses: golden the answer of
// the one host that can, and let the others print that they cannot. That
// leaves the refusing hosts unchecked by the suite, which is exactly where a
// silent no-op would hide.
//
// Nothing here prints a number the device answered. A GPU's name, its largest
// buffer and its memory budget name one machine — and not even that: the iOS
// Simulator reports a different device, no unified memory on a machine that
// has it, and a 256 MB buffer limit against the Mac's 9.5 GB. A golden with
// any of those in it would be a golden for one computer.
package main

import cortado.platform
import cortado.surface
import cortado.widgets
import cortado.motion
import cortado.gpu
import std.io

// Whether what happened is what this platform said would happen.
//
// Written as a function rather than `==` at every call site because the whole
// file is this one comparison and it deserves a name: `promised` is what
// `platform.Capability.gpu` answered, `happened` is what the call did.
fn agrees(promised: bool, happened: bool) -> bool {
    return promised == happened
}


fn drive() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.headless)
    app.check_abi()?

    let promised: bool = platform.Capability.gpu.available()

    io.println("-- the promise --")
    // Every language, asked one at a time, so a host that offered one it
    // cannot compile for would be caught rather than averaged away.
    var offered: int = 0
    let languages: List<gpu.ShaderLanguage> = gpu.ShaderLanguage.all()
    for language: gpu.ShaderLanguage in languages {
        if language.accepted() { offered = offered + 1 }
    }
    io.println("  cortado has a name for this many languages: {languages.len()}")
    io.println("  a shading language is offered exactly where there is a GPU: {agrees(promised, offered > 0)}")
    io.println("  and the host offers none this build has no name for: {gpu.ShaderLanguage.unnamed() == 0}")

    var opened: bool = false
    var named: bool = false
    var name_not_empty: bool = false
    // Counted against how many limits there *are*, not against how many were
    // asked. A host with no device asks none, and "0 of 0 answered" would be
    // true for the wrong reason — the kind of green a gate is supposed to make
    // impossible.
    let every_limit: int = gpu.GpuLimit.all().len()
    var limits_sane: int = 0
    var unified_is_a_yes_or_no: bool = false
    var stale_after_close: bool = false
    var second_close_is_quiet: bool = false
    var refused_as_a_widget: bool = false

    match gpu.Device.open() {
        ok(card) => {
            opened = true
            var device: gpu.Device = card
            match device.name() {
                ok(text) => { named = true; name_not_empty = text.len() > 0 }
                err(problem) => { named = false }
            }
            let keys: List<gpu.GpuLimit> = gpu.GpuLimit.all()
            for which: gpu.GpuLimit in keys {
                match device.limit(which) {
                    // The memory budget is the one that may legitimately be
                    // zero: the driver has no opinion, and the iOS Simulator's
                    // device says exactly that. Negative would be a bug, so a
                    // negative answer does not count as an answer.
                    ok(value) => { if value >= 0.0 { limits_sane = limits_sane + 1 } }
                    err(problem) => {}
                }
            }
            match device.shares_memory() {
                ok(shared) => { unified_is_a_yes_or_no = true }
                err(problem) => { unified_is_a_yes_or_no = false }
            }

            // A device is not a widget, and the handle table says so rather
            // than letting an animation attach to one. This is the guard that
            // makes a handle worth having: a mixed-up integer is a typed
            // refusal, not a message sent to a Metal object.
            match motion.Animation.on(device.handle(), motion.Animatable.opacity) {
                ok(moving) => { refused_as_a_widget = false }
                err(problem) => { refused_as_a_widget = true }
            }

            device.close()?
            // Closed, so the slot's generation moved on: the device object is
            // still here in Beans, and every call it makes is refused. That is
            // the handle doing its job — an address could not tell a closed
            // device from a live one until it crashed.
            match device.name() {
                ok(again) => { stale_after_close = false }
                err(problem) => { stale_after_close = problem.kind == "stale_handle" }
            }
            match device.close() {
                ok(again) => { second_close_is_quiet = !again }
                err(problem) => { second_close_is_quiet = false }
            }
        }
        err(problem) => {
            opened = false
        }
    }

    io.println("-- what a device answers, or refuses --")
    io.println("  one opens exactly where the capability says so: {agrees(promised, opened)}")
    io.println("  it has a name exactly where one opened: {agrees(promised, named)}")
    io.println("  the name is never empty: {agrees(promised, name_not_empty)}")
    io.println("  unified memory is a yes or a no: {agrees(promised, unified_is_a_yes_or_no)}")
    io.println("  a device answers this many limits: {every_limit}")
    io.println("  it answered every one of them, and none was negative: {agrees(promised, limits_sane == every_limit)}")

    io.println("-- refusals --")
    io.println("  a device is refused where a widget belongs: {agrees(promised, refused_as_a_widget)}")
    io.println("  every call on it is refused once it is closed: {agrees(promised, stale_after_close)}")
    io.println("  closing it twice is quiet rather than an error: {agrees(promised, second_close_is_quiet)}")

    return ok(true)
}

fn main() {
    match drive() {
        ok(done) => { io.println("drove={done}") }
        err(problem) => { io.println("{problem.kind}: {problem.msg}") }
    }
}
