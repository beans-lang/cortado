// commands.b — the `cortado` command line.
//
// One binary, the way `dotnet` is one binary: the project is found by walking
// up from where you are, the configuration is named rather than spelled out in
// compiler flags, and every command that compiles anything regenerates the
// markup first so the two halves of a screen cannot be built out of step.
//
//     cortado init myapp            a project, with a screen in it
//     cortado build                 Debug, into build/debug/
//     cortado build -c Release      -O3, NDEBUG, into build/release/
//     cortado run                   build, then launch it
//     cortado check                 build nothing; --drift for a gate
//     cortado generate              the markup only
//     cortado clean                 remove build/
//
// **Everything this tool says about its own progress goes to stderr.** Only
// data goes to stdout: the JSON `vocabulary` prints, the Beans `generate
// --stdout` prints, and whatever the program `run` launched prints for itself.
// That is the ordinary Unix split, and here it is load-bearing rather than
// tidy: `io.println` is block-buffered when stdout is not a terminal, so a
// `watch` writing its progress there showed nothing at all until it was killed
// — a command that prints as it works has to print on the unbuffered stream.
//
// `cortado-bx` is still here and still means what it meant — it calls
// `generate` below, so there is one implementation of the directory walk and
// one of the mirror rule rather than two that agree until they do not.

package cli

import std.io
import std.os
import std.fs
import std.path
import cortado.bx

/// The configuration a command works in, from `-c`/`--configuration`, or the
/// two shorthands that match what `beansc` itself calls them.
fn wanted_profile(manifest: AppManifest, named: string) -> Result<Profile> {
    if named == "" { return manifest.profile("debug") }
    let lowered: string = named.to_lower()
    return manifest.profile(lowered)
}

pub fn usage() {
    io.eprintln("usage: cortado <command> [options]")
    io.eprintln("")
    io.eprintln("commands:")
    io.eprintln("  init <name>    write a project: a screen, a service, and the manifests")
    io.eprintln("  build          regenerate the markup, then compile")
    io.eprintln("  run            build, then launch it; everything after -- goes to the program")
    io.eprintln("  check          regenerate and type-check; nothing is compiled")
    io.eprintln("  generate       compile the markup and stop")
    io.eprintln("  watch          build and run, and do it again on every change")
    io.eprintln("  clean          remove the build directory")
    io.eprintln("  publish        a Release build, wrapped as a platform bundle")
    io.eprintln("  vocabulary     print cortado's .bx surface as JSON, for an editor")
    io.eprintln("  version        print the version and stop")
    io.eprintln("")
    io.eprintln("options:")
    io.eprintln("  -c, --configuration <debug|release>   which profile (default: debug)")
    io.eprintln("      --release / --debug               the same two, spelled the short way")
    io.eprintln("      --drift                           (check) fail on a stale generated file")
    io.eprintln("      --generated                       (clean) remove generated/ as well")
    io.eprintln("      --cortado <path>                  (init) where the cortado checkout is")
    io.eprintln("")
    io.eprintln("publish options (wrapping a loose binary rather than a project):")
    io.eprintln("  --binary <path>       the built file to wrap")
    io.eprintln("  --name <Name>         what the bundle is called")
    io.eprintln("  --identifier <id>     the bundle identifier")
    io.eprintln("  --icon <file.icns>    an icon")
    io.eprintln("  --app-version <v>     the version the plist carries")
    io.eprintln("  --plist KEY=sentence  one Info.plist key; repeatable")
    io.eprintln("")
    io.eprintln("generate options:")
    io.eprintln("  -o <path>          write the generated Beans to <path> (one input only)")
    io.eprintln("  --stdout           write the generated Beans to stdout")
    io.eprintln("  --out <dir>        the root the mirror is written under (default: generated)")
    io.eprintln("  --builder <module> the module Builder comes from (default: cortado.component)")
    io.eprintln("  --package <name>   the package the generated file declares")
}

/// Everything one invocation asked for.
class Parsed {
    pub command: string = ""
    pub configuration: string = ""
    pub positionals: List<string> = []
    pub passthrough: List<string> = []
    pub drift: bool = false
    pub clean_generated: bool = false
    pub cortado_path: string = ""
    /// `publish --binary`: wrap this file rather than a project's output.
    pub binary: string = ""
    pub app_name: string = ""
    pub identifier: string = ""
    pub icon: string = ""
    pub app_version: string = ""
    pub plist: List<string> = []
    pub generate: GenerateOptions = new GenerateOptions()

    pub fn init() {}
}

fn need_value(arguments: List<string>, index: int, flag: string) -> Result<string> {
    if index >= arguments.len() {
        return err("{flag} needs a value after it", "usage")
    }
    return ok(arguments[index])
}

fn parse(arguments: List<string>) -> Result<Parsed> {
    var parsed: Parsed = new Parsed()
    parsed.command = arguments[0]
    var index: int = 1
    var after_dashes: bool = false
    for index < arguments.len() {
        let one: string = arguments[index]
        if after_dashes {
            parsed.passthrough.push(one)
            index += 1
            continue
        }
        if one == "--" {
            after_dashes = true
            index += 1
            continue
        }
        if one == "-c" || one == "--configuration" {
            parsed.configuration = need_value(arguments, index + 1, one)?
            index += 2
            continue
        }
        if one == "--release" || one == "--debug" {
            parsed.configuration = one.slice(2, one.len())
            index += 1
            continue
        }
        if one == "--drift" { parsed.drift = true; index += 1; continue }
        if one == "--generated" {
            parsed.clean_generated = true
            index += 1
            continue
        }
        if one == "--cortado" {
            parsed.cortado_path = need_value(arguments, index + 1, one)?
            index += 2
            continue
        }
        if one == "--binary" {
            parsed.binary = need_value(arguments, index + 1, one)?
            index += 2
            continue
        }
        if one == "--name" {
            parsed.app_name = need_value(arguments, index + 1, one)?
            index += 2
            continue
        }
        if one == "--identifier" {
            parsed.identifier = need_value(arguments, index + 1, one)?
            index += 2
            continue
        }
        if one == "--icon" {
            parsed.icon = need_value(arguments, index + 1, one)?
            index += 2
            continue
        }
        if one == "--app-version" {
            parsed.app_version = need_value(arguments, index + 1, one)?
            index += 2
            continue
        }
        if one == "--plist" {
            parsed.plist.push(need_value(arguments, index + 1, one)?)
            index += 2
            continue
        }
        if one == "--stdout" {
            parsed.generate.to_stdout = true
            index += 1
            continue
        }
        if one == "-o" {
            parsed.generate.output = need_value(arguments, index + 1, one)?
            index += 2
            continue
        }
        if one == "--out" {
            parsed.generate.out_root = need_value(arguments, index + 1, one)?
            index += 2
            continue
        }
        if one == "--builder" {
            parsed.generate.builder_module = need_value(arguments, index + 1, one)?
            index += 2
            continue
        }
        if one == "--package" {
            parsed.generate.package_name = need_value(arguments, index + 1, one)?
            index += 2
            continue
        }
        if one.starts_with("-") {
            return err("{one} is not an option cortado has", "usage")
        }
        parsed.positionals.push(one)
        index += 1
    }
    return ok(parsed)
}

fn do_init(parsed: Parsed) -> Result<bool> {
    if parsed.positionals.len() != 1 {
        return err("init takes one name: cortado init <name>", "usage")
    }
    let name: string = parsed.positionals[0]
    return scaffold(name, path.name(name), parsed.cortado_path)
}

fn do_build(parsed: Parsed) -> Result<bool> {
    let project: Project = open_project(".")?
    let profile: Profile = wanted_profile(project.manifest, parsed.configuration)?
    let built: Built = build_project(project, profile)?
    io.eprintln("built {built.binary} ({built.profile})")
    return ok(true)
}

fn do_run(parsed: Parsed) -> Result<int> {
    let project: Project = open_project(".")?
    let profile: Profile = wanted_profile(project.manifest, parsed.configuration)?
    let built: Built = build_project(project, profile)?
    return launch(project, built.binary, parsed.passthrough)
}

fn do_watch(parsed: Parsed) -> Result<int> {
    let project: Project = open_project(".")?
    let profile: Profile = wanted_profile(project.manifest, parsed.configuration)?
    return watch_project(project, profile, parsed.passthrough)
}

fn do_check(parsed: Parsed) -> Result<bool> {
    let project: Project = open_project(".")?
    if parsed.drift {
        var folders: List<string> = []
        for folder: string in project.markup {
            folders.push(path.join(project.root, folder))
        }
        if folders.is_empty() {
            io.eprintln("no markup in this project, so nothing can be stale")
            return ok(true)
        }
        var options: GenerateOptions = new GenerateOptions()
        let stale: List<Stale> = drift(folders, options)?
        if stale.is_empty() {
            io.eprintln("every generated file matches its markup")
            return ok(true)
        }
        for one: Stale in stale {
            if one.missing {
                io.eprintln("missing: {one.target} — {one.source} was never generated")
            } else {
                io.eprintln("stale:   {one.target} — {one.source} has moved on")
            }
        }
        return err(
            "{stale.len()} generated file(s) no longer match their markup — run 'cortado generate'",
            "drift")
    }
    check_project(project)?
    return ok(true)
}

fn do_generate(parsed: Parsed) -> Result<bool> {
    var inputs: List<string> = []
    for one: string in parsed.positionals { inputs.push(one) }
    if inputs.is_empty() {
        let project: Project = open_project(".")?
        for folder: string in project.markup {
            inputs.push(path.join(project.root, folder))
        }
        if inputs.is_empty() {
            return err(
                "this project has no markup folders — add 'markup <dir>' to cortado.pot",
                "no_markup")
        }
    }
    let made: int = generate(inputs, parsed.generate)?
    if !parsed.generate.to_stdout && !parsed.generate.check_only {
        io.eprintln("generated {made} file(s)")
    }
    return ok(true)
}

fn do_publish(parsed: Parsed) -> Result<bool> {
    // Wrapping a loose binary: no project, everything from the command line.
    // This is what `tools/bundle.sh` calls, so that a built example can be
    // bundled without being made into a project first.
    if parsed.binary != "" {
        var loose: AppManifest = new AppManifest()
        loose.identifier = parsed.identifier
        loose.icon = parsed.icon
        if parsed.app_version != "" { loose.version = parsed.app_version }
        for pair: string in parsed.plist {
            match pair.find("=") {
                some(at) => {
                    loose.plist.push(new PlistEntry(
                        pair.slice(0, at), pair.slice(at + 1, pair.len())))
                }
                none => {
                    return err(
                        "--plist wants KEY=sentence, and '{pair}' has no '='",
                        "usage")
                }
            }
        }
        var name: string = parsed.app_name
        if name == "" { name = path.name(parsed.binary) }
        return publish_binary(parsed.binary, loose, name)
    }
    let project: Project = open_project(".")?
    // Release unless asked otherwise. Shipping a Debug build is a thing people
    // do by accident and never on purpose, so the default is the one that is
    // almost always meant, and `-c Debug` is there for the other time.
    var wanted: string = parsed.configuration
    if wanted == "" { wanted = "release" }
    let profile: Profile = wanted_profile(project.manifest, wanted)?
    return publish_project(project, profile)
}

fn do_clean(parsed: Parsed) -> Result<bool> {
    let project: Project = open_project(".")?
    var removed: int = 0
    let target: string = path.join(project.root, "build")
    if Dir.exists(target) {
        Dir.remove_all(target)?
        io.eprintln("removed build")
        removed += 1
    }
    // `generated/` is source: it is checked in, a clone builds from it with
    // plain `beansc`, and `cortado check --drift` is what keeps it honest. So
    // removing it is asked for by name rather than implied by "clean".
    if parsed.clean_generated {
        let made: string = path.join(project.root, "generated")
        if Dir.exists(made) {
            Dir.remove_all(made)?
            io.eprintln("removed generated")
            removed += 1
        }
    }
    if removed == 0 { io.eprintln("nothing to remove") }
    return ok(true)
}

/// Run one command line. Answers the process's exit status.
pub fn main_with(arguments: List<string>) -> int {
    if arguments.is_empty() {
        usage()
        return 2
    }
    let command: string = arguments[0]
    if command == "--help" || command == "-h" || command == "help" {
        usage()
        return 0
    }
    if command == "--version" || command == "-V" || command == "version" {
        io.println("cortado {CORTADO_VERSION}")
        return 0
    }
    if command == "vocabulary" {
        if arguments.len() > 1 {
            io.eprintln("cortado: vocabulary takes no arguments — it prints cortado's own surface")
            return 2
        }
        io.print(bx.vocabulary_json())
        return 0
    }

    let known: List<string> =
        ["init", "build", "run", "check", "generate", "clean", "watch",
         "publish"]
    var recognised: bool = false
    for one: string in known {
        if one == command { recognised = true }
    }
    if !recognised {
        io.eprintln("cortado: {command} is not a command")
        usage()
        return 2
    }

    var parsed: Parsed = new Parsed()
    match parse(arguments) {
        ok(answer) => { parsed = answer }
        err(problem) => {
            io.eprintln("cortado: {problem.msg}")
            if problem.kind == "usage" { usage() }
            return 2
        }
    }

    if command == "run" || command == "watch" {
        let outcome: Result<int> =
            if command == "run" { do_run(parsed) } else { do_watch(parsed) }
        match outcome {
            ok(status) => { return status }
            err(problem) => {
                io.eprintln("cortado: {problem.msg}")
                return 1
            }
        }
    }

    let outcome: Result<bool> =
        if command == "init" { do_init(parsed) }
        else if command == "build" { do_build(parsed) }
        else if command == "check" { do_check(parsed) }
        else if command == "generate" { do_generate(parsed) }
        else if command == "publish" { do_publish(parsed) }
        else { do_clean(parsed) }

    match outcome {
        ok(done) => { return 0 }
        err(problem) => {
            io.eprintln("cortado: {problem.msg}")
            if problem.kind == "usage" { usage() }
            return 1
        }
    }
}

/// `cortado-bx`'s command line, which is `cortado generate` under three older
/// names.
///
/// The alias is kept because the drift gate, the editors' vocabulary and every
/// README line that predates `cortado` all name it, and because a tool that
/// only compiles markup is a reasonable thing to keep on a machine that never
/// builds an application. What it is not is a second implementation: `build`
/// and `check` below are the same `generate` and `drift` the project commands
/// call, so the two cannot come to disagree about what is in a folder.
pub fn bx_main_with(arguments: List<string>) -> int {
    if arguments.is_empty() {
        bx_usage()
        return 2
    }
    let command: string = arguments[0]
    if command == "--help" || command == "-h" || command == "help" {
        bx_usage()
        return 0
    }
    if command == "--version" || command == "-V" || command == "version" {
        io.println("cortado-bx {CORTADO_VERSION}")
        return 0
    }
    if command == "vocabulary" {
        if arguments.len() > 1 {
            io.eprintln("cortado-bx: vocabulary takes no arguments — it prints cortado's own surface")
            return 2
        }
        io.print(bx.vocabulary_json())
        return 0
    }
    if command != "build" && command != "check" {
        io.eprintln("cortado-bx: {command} is not a command — the three are build, check and vocabulary")
        bx_usage()
        return 2
    }
    var parsed: Parsed = new Parsed()
    match parse(arguments) {
        ok(answer) => { parsed = answer }
        err(problem) => {
            io.eprintln("cortado-bx: {problem.msg}")
            bx_usage()
            return 2
        }
    }
    if parsed.positionals.is_empty() {
        io.eprintln("cortado-bx: no input files")
        bx_usage()
        return 2
    }
    if command == "check" { parsed.generate.check_only = true }
    match generate(parsed.positionals, parsed.generate) {
        ok(made) => { return 0 }
        err(problem) => {
            io.eprintln("cortado-bx: {problem.msg}")
            return 1
        }
    }
}

fn bx_usage() {
    io.eprintln("usage: cortado-bx <command> [options] <file.bx>...")
    io.eprintln("")
    io.eprintln("commands:")
    io.eprintln("  build       compile each file into generated/, mirroring its path")
    io.eprintln("              an input may be a directory: every .bx under it, however deep")
    io.eprintln("  check       parse and emit, and write nothing")
    io.eprintln("  vocabulary  print cortado's .bx surface as JSON, for an editor")
    io.eprintln("")
    io.eprintln("options:")
    io.eprintln("  -o <path>          write the generated Beans to <path> (one input only)")
    io.eprintln("  --stdout           write the generated Beans to stdout")
    io.eprintln("  --builder <module> the module Builder comes from (default: cortado.component)")
    io.eprintln("  --package <name>   the package the generated file declares")
    io.eprintln("  --out <dir>        the root the mirror is written under (default: generated)")
    io.eprintln("")
    io.eprintln("`cortado generate` is the same work under the tool that also builds and")
    io.eprintln("runs a project; this command is its older name and calls straight into it.")
}

/// The whole of the binary's `main`.
pub fn run_cli() {
    let status: int = main_with(os.args())
    if status != 0 { os.exit(status) }
}
