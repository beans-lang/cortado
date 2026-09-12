// The computer a program is running on, as opposed to anything it drew.
//
// Two questions — **can I reach anything, and what is this costing** — and the
// reason they come before the other six device services: **neither is
// privacy-gated.** Every call here was run from a bare binary with no bundle
// and no usage description, across a turn of the run loop, and the process was
// alive afterwards. So unlike `tests/permission.b`, which can only ever report
// that it has no privacy identity of its own, this file gets real answers on
// an ordinary leg.
//
// Cross-host, and in the agreement shape — which matters more here than
// anywhere else in the suite, because **every one of these answers is about
// the machine the test is running on.** A line asserting "there is a network"
// would be a line about somebody's office, and a line asserting "the battery
// is half full" would go red at teatime. So each line says what cortado
// *promised* against what came back: a path that is reachable names a medium,
// a charge is between nothing and full or there is no battery, a state is one
// of the five the header names.
package main

import cortado.platform
import cortado.surface
import cortado.device
import cortado.host
import cortado.events
import std.io

class Heard {
    pub nets: int = 0
    pub powers: int = 0
    pub fn init() {}
}

fn refused_as(answer: Result<f64>, kind: string) -> bool {
    match answer {
        ok(value) => { return false }
        err(problem) => { return problem.kind == kind }
    }
}

fn drive() -> Result<bool> {
    var app: surface.Application = new surface.Application(platform.AppRole.headless)
    app.check_abi()?

    io.println("-- what this platform has --")
    let knows_net: bool = device.Machine.knows_network()
    let knows_power: bool = device.Machine.knows_power()
    io.println("  the capability and the question agree about the network: {knows_net == platform.Capability.network.available()}")
    io.println("  and about the power: {knows_power == platform.Capability.power.available()}")

    let tally: Heard = new Heard()
    // Registering is also what starts the platform's own monitor, which is why
    // there is no watch call: a host learns that somebody wants a kind the
    // moment the first handler arrives, and that is the same decision.
    app.router.on(host_none(), events.EventKind.net_changed,
        fn(event: events.UiEvent) { tally.nets = tally.nets + 1 })
    app.router.on(host_none(), events.EventKind.power_changed,
        fn(event: events.UiEvent) { tally.powers = tally.powers + 1 })

    io.println("-- the network --")
    // Asked, then a turn of the loop, then asked again. Two of the four hosts
    // answer at once and two answer a turn later, because nw_path_monitor has
    // no synchronous read at all — so this is what one program does on every
    // platform rather than two programs.
    let first: device.NetworkPath = device.Machine.path()?
    app.run_for(0.3)?
    let settled: device.NetworkPath = device.Machine.path()?

    // Not "there is a network": that would be a line about somebody's office.
    // What is asserted is that whatever came back is one of the six the header
    // names, and that a path which says it is reachable is not also `none`.
    io.println("  the answer is one this version knows: {settled.code() >= 0 && settled.code() <= 5}")
    io.println("  and a path that is reachable is not nothing: {settled.reachable() != (settled == device.NetworkPath.none || settled == device.NetworkPath.unknown)}")
    // Before anything answered, `unknown` — and a program must not read that
    // as permission to go ahead.
    io.println("  and nothing has answered is not the same as yes: {!device.NetworkPath.unknown.reachable()}")

    // Not "is it expensive" — that is a fact about somebody's office. What is
    // asserted is the rule that must hold whatever the answer: **a path that
    // reaches nothing costs nothing.** A host that left stale flags behind
    // when the network went would fail this and nothing else would see it.
    let costly: bool = device.Machine.expensive()?
    let limited: bool = device.Machine.constrained()?
    io.println("  nothing to reach costs nothing: {settled.reachable() || (!costly && !limited)}")

    io.println("-- the power --")
    let source: device.PowerSource = device.Machine.power()?
    io.println("  what is running the machine is one of the three: {source.code() >= 0 && source.code() <= 2}")

    // A charge or an honest refusal, and never a number invented for a machine
    // with no battery — which is the failure this line exists for: a program
    // drawing a meter should draw nothing rather than a full one.
    var level: f64 = -1.0
    var no_battery: bool = false
    match device.Machine.charge() {
        ok(full) => { level = full }
        err(problem) => { no_battery = problem.kind == "unsupported" }
    }
    let sane: bool = level >= 0.0 && level <= 1.0
    io.println("  a charge is between nothing and full, or there is no battery: {sane != no_battery}")

    // Asked twice, because these are reads of the system and a read that
    // changed the thing it read would be the bug worth catching — the iOS host
    // turns battery monitoring on the first time it is asked, which is exactly
    // the shape that goes wrong.
    let saving: bool = device.Machine.saving()?
    let again: bool = device.Machine.saving()?
    let twice_source: device.PowerSource = device.Machine.power()?
    io.println("  asking twice gives the same answer: {saving == again && twice_source == source}")

    let heat: device.ThermalState = device.Machine.heat()?
    io.println("  how hot it is, is one of the five: {heat.code() >= 0 && heat.code() <= 4}")
    // Only Apple's platforms have a scale, so `unknown` is the answer on two
    // of the four — and a program that did less work because nobody knew would
    // do less for ever there.
    io.println("  and not knowing is not a reason to do less: {!device.ThermalState.unknown.under_strain()}")

    io.println("-- the names --")
    // Three small tables, and the failure a table invites is two rows with one
    // word. Asked here for the same reason the key names are.
    var every_name_once: bool = true
    var paths: Map<string, bool> = {}
    for path: device.NetworkPath in [device.NetworkPath.unknown, device.NetworkPath.none,
                                     device.NetworkPath.wifi, device.NetworkPath.wired,
                                     device.NetworkPath.cellular, device.NetworkPath.other] {
        if paths.contains_key(path.name()) { every_name_once = false }
        paths.set(path.name(), true)
        // And the number and the name are two views of one row, so a member
        // that named itself and answered somebody else's number would show up
        // here rather than in whatever program hit it first.
        if device.NetworkPath.of(path.code()) != path { every_name_once = false }
    }
    // A separate map, because these are separate tables: `unknown` is a member
    // of both and pooling them would call that a collision.
    var states: Map<string, bool> = {}
    for state: device.ThermalState in [device.ThermalState.unknown, device.ThermalState.nominal,
                                       device.ThermalState.fair, device.ThermalState.serious,
                                       device.ThermalState.critical] {
        if states.contains_key(state.name()) { every_name_once = false }
        states.set(state.name(), true)
        if device.ThermalState.of(state.code()) != state { every_name_once = false }
    }
    var sources: Map<string, bool> = {}
    for one: device.PowerSource in [device.PowerSource.unknown, device.PowerSource.mains,
                                    device.PowerSource.battery] {
        if sources.contains_key(one.name()) { every_name_once = false }
        sources.set(one.name(), true)
        if device.PowerSource.of(one.code()) != one { every_name_once = false }
    }
    io.println("  no two in a table share a word, and each reads back as itself: {every_name_once}")
    io.println("  and there are six paths, five heats and three sources: {paths.len() == 6 && states.len() == 5 && sources.len() == 3}")

    app.shutdown()
    return ok(true)
}

/// The machine's events name no widget — a network is not a control — so they
/// are routed against the handle that means "nothing".
fn host_none() -> host.Handle {
    return host.Handle.none()
}

fn main() {
    match drive() {
        ok(done) => { io.println("drove={done}") }
        err(problem) => { io.println("{problem.kind}: {problem.msg}") }
    }
}
