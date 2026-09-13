// generate.b — the `.bx` compiler's driver.
//
// This was `examples/cortado_bx.b`'s whole body. It moved here so that
// `cortado generate`, `cortado build`, `cortado check --drift` and the
// `cortado-bx` alias all walk directories the same way and put output in the
// same place — three of those are new, and a second implementation of "which
// files are in this folder" is exactly the thing that answers one short.
//
// Two rules, both of them about not missing a file:
//
// **A directory stands for every `.bx` under it, however deep.** A shell glob
// is not recursive: `screens/*.bx` silently misses `screens/parts/`, and what
// that produces is a *stale* generated file that still compiles, still renders
// last week's screen, and says nothing. A directory with no markup in it is an
// error rather than no work.
//
// **The mirror hangs off the module root**, the nearest directory above the
// source with a `beans.pot` — not off the working directory. So
// `cortado generate screens/home.bx` from the project and
// `cortado generate myapp/screens/home.bx` from above it write the same file.

package cli

import std.fs
import std.path
import std.io
import cortado.bx

/// How to generate.
pub class GenerateOptions {
    /// The root the mirror is written under, relative to the module root.
    pub out_root: string = "generated"
    /// The module `Builder` and `Component` come from.
    pub builder_module: string = "cortado.component"
    /// The package the generated file declares. Empty: the folder decides.
    pub package_name: string = ""
    /// `-o`: one named output, and therefore one input.
    pub output: string = ""
    /// Write to stdout instead of to the mirror.
    pub to_stdout: bool = false
    /// Parse and emit, and write nothing.
    pub check_only: bool = false

    pub fn init() {}
}

/// The module root above a source file, or `""` when there is none.
pub fn module_root_of(source: string) -> string {
    let folder: string = bx.directory_of(source)
    var root: string = folder
    if root == "" { root = "." }
    var depth: int = 0
    for depth < 64 {
        if fs.exists(path.join(root, "beans.pot")) { return root }
        var up: string = path.parent(root)
        if up == "" {
            if root == "." { break }
            up = "."
        }
        if up == root { break }
        root = up
        depth += 1
    }
    return ""
}

/// Where one source file's generated half goes.
///
/// With no `beans.pot` anywhere above it — a loose file, a scratch test — the
/// mirror hangs off the file's own directory instead, which is the only other
/// answer that is not a guess.
pub fn mirror_for(source: string, out_root: string) -> string {
    let root: string = module_root_of(source)
    if root != "" {
        return bx.mirror_path(root, out_root, source,
                              strip_prefix(source, root))
    }
    var here: string = bx.directory_of(source)
    if here == "" { here = "." }
    return bx.generated_path_under(path.join(here, out_root),
                                   bx.base_name(source))
}

/// How the generated file's header should name this source.
///
/// Relative to the module root, always — so the bytes a source compiles to do
/// not depend on where the tool was run from or how the path was spelled.
/// Without this, `cortado generate screens` and `cortado generate ./screens`
/// write different files and a drift gate calls one of them stale.
pub fn source_label_for(source: string) -> string {
    let root: string = module_root_of(source)
    if root == "" { return trimmed_dot(source) }
    return trimmed_dot(strip_prefix(source, root))
}

/// `./screens/home.bx` -> `screens/home.bx`.
fn trimmed_dot(value: string) -> string {
    if value.starts_with("./") { return value.slice(2, value.len()) }
    return value
}

/// `source` with `root/` taken off the front, or `source` unchanged when it
/// does not start there.
pub fn strip_prefix(source: string, root: string) -> string {
    if root == "." || root == "" { return source }
    let marked: string = "{root}/"
    if source.starts_with(marked) {
        return source.slice(marked.len(), source.len())
    }
    return source
}

/// Every input, with each directory replaced by the `.bx` files under it.
pub fn expand(given: List<string>, into: List<string>) -> Result<bool> {
    for one: string in given {
        if !Dir.exists(one) {
            into.push(one)
            continue
        }
        var here: int = 0
        for under: string in Dir.walk(one)? {
            if !under.ends_with(".bx") { continue }
            into.push(path.join(one, under))
            here += 1
        }
        if here == 0 {
            return err("{one} is a directory with no .bx files under it",
                       "no_markup")
        }
    }
    return ok(true)
}

fn bx_options(options: GenerateOptions, source: string) -> bx.Options {
    var chosen: bx.Options = new bx.Options()
    chosen.cortado_module = options.builder_module
    chosen.package_name = options.package_name
    chosen.source_label = source_label_for(source)
    return chosen
}

/// Compile every input. Answers how many files were written.
///
/// Every refusal is printed as it happens rather than collected, because a
/// screen that failed to compile is a diagnostic somebody has to read, and the
/// next screen's diagnostic is worth reading too — so one bad file does not
/// hide the other four.
pub fn generate(inputs: List<string>, options: GenerateOptions) -> Result<int> {
    var sources: List<string> = []
    expand(inputs, sources)?
    if sources.is_empty() {
        return err("no .bx files to generate", "no_markup")
    }
    if options.output != "" && sources.len() > 1 {
        return err(
            "-o names one output and there are {sources.len()} inputs",
            "usage")
    }

    var written: int = 0
    var failed: int = 0
    for source: string in sources {
        let compiled: bx.Compiled = bx.compile_file(source, bx_options(options, source))
        if !compiled.is_ok() {
            io.eprintln(compiled.report(source))
            failed += 1
            continue
        }
        if options.check_only { continue }
        if options.to_stdout {
            io.print(compiled.source)
            continue
        }
        var target: string = options.output
        if target == "" { target = mirror_for(source, options.out_root) }
        // The mirror does not exist until something makes it, and a generated
        // tree that failed to be written because a folder was missing is a
        // build that fails for a reason nobody can act on.
        let folder: string = bx.directory_of(target)
        match Dir.create_all(folder) {
            ok(_) => {}
            err(problem) => {
                return err("cannot make {folder}: {problem.msg}", "write")
            }
        }
        fs.write(target, compiled.source)?
        written += 1
    }
    if failed > 0 {
        return err("{failed} of {sources.len()} markup file(s) were refused",
                   "markup")
    }
    return ok(written)
}

/// One generated file that no longer matches its source.
pub class Stale {
    pub source: string = ""
    pub target: string = ""
    /// Empty when the file is merely out of date; a reason when it is missing.
    pub missing: bool = false

    pub fn init(source: string, target: string, missing: bool) {
        self.source = source
        self.target = target
        self.missing = missing
    }
}

/// Regenerate into memory and compare with what is on disk.
///
/// This is what makes checking generated code in safe rather than a liability:
/// a stale file fails a gate instead of shipping. `cortado build` cannot
/// produce one — it regenerates first — but `beansc build` can, and so can a
/// merge, and both are how a project without this check ships last week's
/// screen.
pub fn drift(inputs: List<string>, options: GenerateOptions) -> Result<List<Stale>> {
    var sources: List<string> = []
    expand(inputs, sources)?
    var stale: List<Stale> = []
    for source: string in sources {
        let compiled: bx.Compiled = bx.compile_file(source, bx_options(options, source))
        if !compiled.is_ok() {
            io.eprintln(compiled.report(source))
            return err("{source} was refused", "markup")
        }
        let target: string = mirror_for(source, options.out_root)
        if !fs.exists(target) {
            stale.push(new Stale(source, target, true))
            continue
        }
        let present: string = fs.read(target)?
        if present != compiled.source {
            stale.push(new Stale(source, target, false))
        }
    }
    return ok(move stale)
}

/// Regenerate every markup folder a project declares.
pub fn generate_project(project: Project) -> Result<int> {
    if project.markup.is_empty() { return ok(0) }
    var folders: List<string> = []
    for folder: string in project.markup {
        folders.push(path.join(project.root, folder))
    }
    var options: GenerateOptions = new GenerateOptions()
    return generate(folders, options)
}
