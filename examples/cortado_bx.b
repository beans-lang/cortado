// cortado-bx — the markup compiler's command line.
//
// **Why this is under `examples/` and not at the module root.** cortado is a
// `kind library` module, and a library may only hold a program entry under
// `examples/` or `tests/`. A root-level `package main` file is refused twice
// over — one directory is one package, and a library root declares a normal
// package name rather than `main`. So this is not a demo; it is where the
// binary's entry is allowed to live.
//
// It imports `cortado.bx` and nothing else of cortado's, so it links no
// platform host: the markup compiler is pure Beans over `std.fs` and builds on
// every operating system, including the ones whose host has not been written.
//
//     beansc build examples/cortado_bx.b -o build/cortado-bx
//     build/cortado-bx build pages/counter.bx
//
// Build-time only. It imports `std.fs` and `std.os`; nothing under the module
// root imports `cortado.bx`, so an application that ships a screen never
// links a compiler.
package main

import std.fs
import std.path
import std.io
import std.os
import cortado.bx

/// Where one source file's generated half goes.
///
/// The mirror hangs off the **module root** — the nearest directory above the
/// source with a `beans.pot` in it — not off the working directory. So
/// `cortado-bx build site/checkout.bx` from the module and
/// `cortado-bx build examples/markup/site/checkout.bx` from the workspace
/// write the same file, and a build script cannot put a generated tree
/// somewhere nobody expects by being run from the wrong place.
///
/// With no `beans.pot` anywhere above it — a loose file, a scratch test — the
/// mirror hangs off the file's own directory instead, which is the only other
/// answer that is not a guess.
fn mirror_for(source: string, out_root: string) -> string {
    var folder: string = bx.directory_of(source)
    // A relative path runs out of parents before it runs out of directories —
    // `path.parent("site")` is "" — so the walk climbs through "." rather than
    // stopping at the first bare segment.
    var root: string = folder
    if root == "" { root = "." }
    var depth: int = 0
    for depth < 64 {
        if fs.exists(path.join(root, "beans.pot")) {
            return bx.mirror_path(root, out_root, source, strip_prefix(source, root))
        }
        var up: string = path.parent(root)
        if up == "" {
            if root == "." { break }
            up = "."
        }
        if up == root { break }
        root = up
        depth = depth + 1
    }
    var here: string = folder
    if here == "" { here = "." }
    return bx.generated_path_under(path.join(here, out_root), bx.base_name(source))
}

/// `source` with `root/` taken off the front, or `source` unchanged when it
/// does not start there.
fn strip_prefix(source: string, root: string) -> string {
    if root == "." || root == "" { return source }
    let marked: string = "{root}/"
    if source.starts_with(marked) {
        return source.slice(marked.len(), source.len())
    }
    return source
}

fn usage() {
    io.eprintln("usage: cortado-bx <command> [options] <file.bx>...")
    io.eprintln("")
    io.eprintln("commands:")
    io.eprintln("  build       compile each file into generated/, mirroring its path")
    io.eprintln("  check       parse and emit, and write nothing")
    io.eprintln("  vocabulary  print cortado's .bx surface as JSON, for an editor")
    io.eprintln("")
    io.eprintln("options:")
    io.eprintln("  -o <path>          write the generated Beans to <path> (one input only)")
    io.eprintln("  --stdout           write the generated Beans to stdout")
    io.eprintln("  --builder <module>   the module Builder comes from (default: cortado.component)")
    io.eprintln("  --package <name>   the package the generated file declares")
    io.eprintln("  --out <dir>        the root the mirror is written under (default: generated)")
    io.eprintln("")
    io.eprintln("A generated file is checked in beside its source, and a drift gate")
    io.eprintln("regenerates and diffs it, so a stale one fails the build rather than")
    io.eprintln("shipping.")
}

fn main() {
    let args: List<string> = os.args()
    if args.is_empty() {
        usage()
        os.exit(2)
    }
    let command: string = args[0]
    if command == "--help" || command == "-h" || command == "help" {
        usage()
        return
    }
    // The vocabulary takes no input file and no option: it is the language,
    // not a translation of anything. `editors/shared/bx.json` is this string,
    // and `tests/w2_editor_data.out` is the same string as a golden, so the
    // gate says the two cannot drift.
    if command == "vocabulary" {
        if args.len() > 1 {
            io.eprintln("cortado-bx: vocabulary takes no arguments — it prints cortado's own surface")
            os.exit(2)
        }
        io.print(bx.vocabulary_json())
        return
    }
    if command != "build" && command != "check" {
        io.eprintln("cortado-bx: {command} is not a command — the three are build, check and vocabulary")
        usage()
        os.exit(2)
    }

    let options: bx.Options = new bx.Options()
    let inputs: List<string> = []
    var output: string = ""
    var out_root: string = "generated"
    var to_stdout: bool = false
    var index: int = 1
    for index < args.len() {
        let arg: string = args[index]
        if arg == "-o" {
            index = index + 1
            if index >= args.len() {
                io.eprintln("cortado-bx: -o needs a path after it")
                os.exit(2)
            }
            output = args[index]
            index = index + 1
            continue
        }
        if arg == "--stdout" {
            to_stdout = true
            index = index + 1
            continue
        }
        if arg == "--out" {
            if index + 1 >= args.len() {
                io.eprintln("cortado-bx: --out needs a directory after it")
                os.exit(2)
            }
            out_root = args[index + 1]
            index = index + 2
            continue
        }
        if arg == "--builder" {
            index = index + 1
            if index >= args.len() {
                io.eprintln("cortado-bx: --builder needs a module path after it")
                os.exit(2)
            }
            options.cortado_module = args[index]
            index = index + 1
            continue
        }
        if arg == "--package" {
            index = index + 1
            if index >= args.len() {
                io.eprintln("cortado-bx: --package needs a name after it")
                os.exit(2)
            }
            options.package_name = args[index]
            index = index + 1
            continue
        }
        if arg.starts_with("-") {
            io.eprintln("cortado-bx: {arg} is not an option cortado-bx has")
            usage()
            os.exit(2)
        }
        inputs.push(arg)
        index = index + 1
    }

    if inputs.is_empty() {
        io.eprintln("cortado-bx: no input files")
        usage()
        os.exit(2)
    }
    if output != "" && inputs.len() > 1 {
        io.eprintln("cortado-bx: -o names one output and there are {inputs.len()} inputs")
        os.exit(2)
    }

    var failed: bool = false
    for path: string in inputs {
        let compiled: bx.Compiled = bx.compile_file(path, options)
        if !compiled.is_ok() {
            io.eprintln(compiled.report(path))
            failed = true
            continue
        }
        if command == "check" { continue }
        if to_stdout {
            io.print(compiled.source)
            continue
        }
        var target: string = output
        if target == "" { target = mirror_for(path, out_root) }
        // The mirror does not exist until something makes it, and a generated
        // tree that failed to be written because a folder was missing is a
        // build that fails for a reason nobody can act on.
        match Dir.create_all(bx.directory_of(target)) {
            ok(_) => {}
            err(problem) => {
                io.eprintln("cortado-bx: cannot make {bx.directory_of(target)}: {problem.msg}")
                failed = true
                continue
            }
        }
        match fs.write(target, compiled.source) {
            ok(_) => {}
            err(problem) => {
                io.eprintln("cortado-bx: cannot write {target}: {problem.msg}")
                failed = true
            }
        }
    }
    if failed { os.exit(1) }
}
