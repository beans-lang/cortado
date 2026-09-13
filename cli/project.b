// project.b — what a cortado project is, and how a command finds it.
//
// A project is a directory with a `beans.pot` in it. That is not a second
// definition of anything: it is the compiler's own rule — `find_root` in
// beans/src/module.b walks up from a file to the nearest manifest, and the
// markup mirror already hangs off the same directory — so a command run from
// `screens/parts/` and the same command run from the root do the same work on
// the same files.
//
// **Markup folders are named, and anything outside them is refused.** A
// project says `markup screens` and `markup components`, or says nothing and
// gets those two if they exist. Either way the whole project is then swept for
// `.bx` files that no markup root covers, and one found is an error. This is
// the same reasoning that makes `cortado generate` take a directory rather
// than a glob: a screen that is never regenerated is a screen that still
// compiles and still renders last week's design, and says nothing.

package cli

import std.fs
import std.path

/// Where a project is, and what is in it.
pub class Project {
    /// The directory holding `beans.pot`.
    pub root: string = ""
    /// The module name `beans.pot` declares.
    pub module_name: string = ""
    /// The entry file, relative to the root.
    pub entry: string = "main.b"
    pub manifest: AppManifest = new AppManifest()
    /// The folders holding `.bx` markup, relative to the root.
    pub markup: List<string> = []

    pub fn init() {}

    /// What the binary is called: `cortado.pot`'s name, else the module name.
    pub fn binary_name() -> string {
        if self.manifest.name != "" { return self.manifest.name }
        return self.module_name
    }
}

/// The directory names a sweep never descends into.
///
/// `generated` holds this tool's own output, `build` holds the compiler's, and
/// a dot directory is somebody's tooling. None of them can hold a source `.bx`
/// that a person wrote, and walking them makes a sweep of a real project cost
/// the whole object cache.
fn skipped_directory(name: string) -> bool {
    return name == "generated" || name == "build" || name == ".git" ||
           name.starts_with(".")
}

/// The nearest directory at or above `start` holding a `beans.pot`.
pub fn find_root(start: string) -> Result<string> {
    var here: string = start
    // A relative path runs out of parents before it runs out of directories —
    // `path.parent(".")` is `""` — so a walk that began at `.` would look in
    // one directory and stop, and `cortado build` from `screens/` would say
    // there is no project. Starting from the absolute path of the working
    // directory is what lets the walk actually climb.
    if here == "" || here == "." { here = Dir.current() }
    var depth: int = 0
    for depth < 64 {
        if fs.exists(path.join(here, "beans.pot")) { return ok(here) }
        var up: string = path.parent(here)
        if up == "" {
            if here == "." { break }
            up = "."
        }
        if up == here { break }
        here = up
        depth += 1
    }
    return err(
        "no beans.pot here or above — run this in a project, or make one with 'cortado init <name>'",
        "no_project")
}

/// The `module` line from a `beans.pot`.
fn read_module_name(root: string) -> Result<string> {
    let file: string = path.join(root, "beans.pot")
    let text: string = fs.read(file)?
    for line: string in text.lines() {
        let trimmed: string = line.trim()
        if !trimmed.starts_with("module ") { continue }
        let rest: string = trimmed.slice(7, trimmed.len()).trim()
        if rest != "" { return ok(rest) }
    }
    return err("{file}: no 'module <name>' line", "manifest")
}

/// Every `.bx` file anywhere in the project that a markup root does not cover.
///
/// A screen in a folder nobody declared is the failure this whole tool exists
/// to make impossible, so it is an error with the fix in it rather than a file
/// quietly left ungenerated.
fn orphan_markup(root: string, covered: List<string>) -> Result<List<string>> {
    var orphans: List<string> = []
    for under: string in Dir.walk(root)? {
        if !under.ends_with(".bx") { continue }
        var inside: bool = false
        for folder: string in covered {
            if under == folder || under.starts_with("{folder}/") {
                inside = true
            }
        }
        if inside { continue }
        // A sweep must not descend into output or tooling, and `Dir.walk`
        // has no filter — so the check is on the path it answered.
        var hidden: bool = false
        for piece: string in under.split("/") {
            if skipped_directory(piece) { hidden = true }
        }
        if hidden { continue }
        orphans.push(under)
    }
    return ok(move orphans)
}

/// The markup folders for a project: what `cortado.pot` said, or the two the
/// scaffolder writes, and then a sweep proving nothing was left out.
fn resolve_markup(root: string, manifest: AppManifest) -> Result<List<string>> {
    var folders: List<string> = []
    if !manifest.markup.is_empty() {
        for named: string in manifest.markup {
            if !Dir.exists(path.join(root, named)) {
                return err(
                    "cortado.pot says 'markup {named}', and {named}/ is not there",
                    "no_markup")
            }
            folders.push(named)
        }
    } else {
        for guess: string in ["screens", "components"] {
            if Dir.exists(path.join(root, guess)) { folders.push(guess) }
        }
    }

    let orphans: List<string> = orphan_markup(root, folders)?
    if !orphans.is_empty() {
        var shown: string = orphans[0]
        var extra: int = orphans.len() - 1
        if extra > 0 { shown = "{shown} (and {extra} more)" }
        if folders.is_empty() {
            return err(
                "{shown} is markup that no folder covers — add 'markup {top_folder(orphans[0])}' to cortado.pot",
                "no_markup")
        }
        return err(
            "{shown} is outside every markup folder, so nothing would regenerate it — add 'markup {top_folder(orphans[0])}' to cortado.pot",
            "no_markup")
    }
    return ok(move folders)
}

/// The first path segment of a relative path, which is the folder a `markup`
/// row would name.
fn top_folder(relative: string) -> string {
    let pieces: List<string> = relative.split("/")
    if pieces.is_empty() { return relative }
    return pieces[0]
}

/// Open the project containing `start`.
pub fn open_project(start: string) -> Result<Project> {
    let root: string = find_root(start)?
    var project: Project = new Project()
    project.root = root
    project.module_name = read_module_name(root)?
    project.manifest = read_manifest(root)?
    project.markup = resolve_markup(root, project.manifest)?
    if !fs.exists(path.join(root, project.entry)) {
        return err(
            "{root}/main.b is not there — a cortado application's entry is main.b, beside beans.pot",
            "no_entry")
    }
    return ok(project)
}
