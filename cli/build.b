// build.b — turning a project and a profile into a `beansc` command line.
//
// **Every build generates first.** That is the whole reason this command
// exists rather than a line in a README: markup and the code built from it are
// two files, and any process where a person can compile one without the other
// eventually ships the pair out of step. Here they cannot be.
//
// **Debug and Release are `beansc`'s two flags, named.** `--debug` is `-O0`
// with frame pointers and DWARF line tables, so a debugger has something to
// attach to; `--release` is `-O3` with `NDEBUG`. Passing neither — which is
// what every cortado build did until now — is a third mode that is
// unoptimised *and* unattachable, which is the worst of both and was nobody's
// intention. The two profiles write to different directories, so switching
// configuration never silently overwrites the other one's binary, and
// `beansc`'s object cache keys on both flags so switching back is not a
// rebuild.

package cli

import std.fs
import std.path
import std.io
import std.os
import std.process

/// Where `beansc` is.
///
/// The same four-step search `test.sh` and every community library's `test.sh`
/// already use, so a checkout built from the tree and an installed release are
/// both found and neither is preferred by accident. `$BEANSC` first, because
/// that is how a gate pins the compiler it means to test.
pub fn find_beansc() -> Result<string> {
    match os.env("BEANSC") {
        some(named) => {
            if fs.exists(named) { return ok(named) }
            return err("$BEANSC is {named}, and there is nothing there",
                       "no_beansc")
        }
        none => {}
    }
    match os.env("BEANS_ROOT") {
        some(root) => {
            let built: string = path.join(path.join(root, "build"), "beansc")
            if fs.exists(built) { return ok(built) }
        }
        none => {}
    }
    match os.env("BEANS_HOME") {
        some(home) => {
            let installed: string = path.join(path.join(home, "bin"), "beansc")
            if fs.exists(installed) { return ok(installed) }
        }
        none => {}
    }
    match os.env("HOME") {
        some(user) => {
            let dot: string = path.join(
                path.join(path.join(user, ".beans"), "bin"), "beansc")
            if fs.exists(dot) { return ok(dot) }
        }
        none => {}
    }
    return ok("beansc")
}

/// What a build produced.
pub class Built {
    /// The binary's path, relative to the project root.
    pub binary: string = ""
    /// The profile it was built with.
    pub profile: string = ""

    pub fn init(binary: string, profile: string) {
        self.binary = binary
        self.profile = profile
    }
}

/// The `beansc` arguments for one profile.
///
/// Kept as its own function because it is what the gate asserts: a golden that
/// prints this list is how "Release really passes --release" stops being
/// something somebody checked once by hand.
pub fn beansc_arguments(project: Project, profile: Profile, entry: string, output: string) -> List<string> {
    var arguments: List<string> = ["build", entry, "-o", output]
    if profile.is_release() {
        arguments.push("--release")
        // `beansc` already drops LTO from a debug build, so this is only ever
        // asked for where it can be honoured.
        if profile.lto { arguments.push("--lto") }
    } else {
        arguments.push("--debug")
    }
    if profile.target != "" {
        arguments.push("--target")
        arguments.push(profile.target)
    }
    if profile.cpu != "" {
        arguments.push("--cpu")
        arguments.push(profile.cpu)
    }
    if profile.features != "" {
        arguments.push("--features")
        arguments.push(profile.features)
    }
    return move arguments
}

/// Where a profile's binary goes, relative to the project root.
pub fn binary_path(project: Project, profile: Profile) -> string {
    return path.join(profile.out, project.binary_name())
}

/// Run `beansc` in the project root and report what it said.
///
/// The whole of `beansc`'s output is collected and printed rather than
/// streamed, because a diagnostic that interleaves two streams is a diagnostic
/// somebody has to read twice — and because a gate diffing this output needs
/// the order to be the same on every machine.
fn run_beansc(project: Project, arguments: List<string>) -> Result<bool> {
    let compiler: string = find_beansc()?
    var command: process.Command = new process.Command(compiler)
    for one: string in arguments { command.arg(one) }
    command.cwd(project.root)
    let finished: process.Output = command.run()?
    // beansc's own output is status too — a build's diagnostics belong beside
    // cortado's, on the stream a person is reading, not on the one they are
    // redirecting into a file.
    let said: string = finished.stdout_text()
    let complained: string = finished.stderr_text()
    if said != "" { io.eprint(said) }
    if complained != "" { io.eprint(complained) }
    if !finished.succeeded() {
        return err("beansc exited {finished.status}", "build")
    }
    return ok(true)
}

/// Generate, then compile.
pub fn build_project(project: Project, profile: Profile) -> Result<Built> {
    let made: int = generate_project(project)?
    if made > 0 { io.eprintln("generated {made} screen(s)") }

    let output: string = binary_path(project, profile)
    let folder: string = path.join(project.root, path.parent(output))
    match Dir.create_all(folder) {
        ok(_) => {}
        err(problem) => {
            return err("cannot make {folder}: {problem.msg}", "build")
        }
    }
    run_beansc(project, beansc_arguments(project, profile, project.entry, output))?
    return ok(new Built(output, profile.name))
}

/// Generate, then check — no binary.
pub fn check_project(project: Project) -> Result<bool> {
    let made: int = generate_project(project)?
    if made > 0 { io.eprintln("generated {made} screen(s)") }
    return run_beansc(project, ["check", project.entry])
}
