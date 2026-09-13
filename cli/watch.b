// watch.b — rebuild and relaunch when something changes.
//
// **It compares content, because nothing can tell it a file changed.** There
// is no modification time reachable from Beans: `std.fs` has `read`, `write`,
// `size`, `exists`, `copy`, `rename` and `remove` and nothing else, and the
// `File` builtin has no `stat` either. So a tick reads every watched file and
// compares its length and its CRC with the last tick's.
//
// That is honestly worse than a kernel watcher — it is O(source bytes) every
// tick rather than O(changes) — and for a project of a few hundred files it is
// well under a megabyte a tick, which is nothing beside the compile it exists
// to trigger. The fix is `fs.modified()` in the beans standard library, which
// is a change to a different repository; smuggling a `stat` in through a C
// source here would put a platform dependency in the one tool that is meant to
// build on the operating systems cortado has no host for.
//
// **Length *and* CRC, not one or the other.** A length alone misses an edit
// that swapped two characters, which is most of the edits a person makes to a
// screen. A CRC alone is a 1-in-4-billion chance of missing one, and this
// costs a machine word to make that chance nought.

package cli

import std.fs
import std.path
import std.io
import std.time

/// How often to look, in milliseconds. Fast enough that a save feels like it
/// was noticed, slow enough that a project is not being read continuously.
fn tick_ms() -> int {
    return 400
}

/// What every watched file looked like last time.
pub class Sentinel {
    root: string
    folders: List<string> = []
    files: List<string> = []
    marks: List<int> = []

    pub fn init(root: string) {
        self.root = root
    }

    pub fn follow(folder: string) {
        self.folders.push(folder)
    }

    /// Every file a change should trigger a rebuild for.
    ///
    /// Markup and Beans both: a screen's `.bx` and the service it injects are
    /// equally the program, and a watch that only noticed markup would leave a
    /// person wondering why editing a service did nothing.
    fn sources() -> Result<List<string>> {
        var found: List<string> = []
        for under: string in Dir.walk(self.root)? {
            if !under.ends_with(".bx") && !under.ends_with(".b") &&
               !under.ends_with(".pot") {
                continue
            }
            var hidden: bool = false
            for piece: string in under.split("/") {
                if piece == "build" || piece.starts_with(".") { hidden = true }
            }
            if hidden { continue }
            found.push(under)
        }
        return ok(move found)
    }

    /// One number standing for a file's contents.
    fn mark(relative: string) -> int {
        match fs.read_bytes(path.join(self.root, relative)) {
            ok(data) => {
                let size: int = data.len()
                return size * 31 + data.crc32(0, size)
            }
            err(problem) => { return -1 }
        }
    }

    /// Take a reading. Answers whether anything moved since the last one.
    ///
    /// A file appearing and a file disappearing both count, which is why the
    /// list of names is compared and not only the marks: adding a screen is a
    /// change a person expects to see picked up.
    pub fn moved() -> Result<bool> {
        let now: List<string> = self.sources()?
        var marks: List<int> = []
        for one: string in now { marks.push(self.mark(one)) }

        var differs: bool = now.len() != self.files.len()
        if !differs {
            var index: int = 0
            for index < now.len() {
                if now[index] != self.files[index] { differs = true }
                if marks[index] != self.marks[index] { differs = true }
                index += 1
            }
        }
        self.files = move now
        self.marks = move marks
        return ok(differs)
    }
}

/// Build, run, and do it again every time a source file moves.
pub fn watch_project(project: Project, profile: Profile, arguments: List<string>) -> Result<int> {
    var sentinel: Sentinel = new Sentinel(project.root)
    io.eprintln("watching {project.root} — every .b, .bx and .pot under it")
    var rounds: int = 0
    for rounds < 100000 {
        rounds += 1
        // Whether the next turn should build straight away. A run that was
        // *stopped* because a file moved must not then wait for a second
        // change: the interrupt that stopped it has already taken the reading
        // that says what moved, so waiting would block until somebody edited
        // something a second time.
        var build_again: bool = false
        match build_project(project, profile) {
            ok(built) => {
                io.eprintln("built {built.binary} ({built.profile})")
                // The reading is taken *after* the build, not before it: a
                // build writes the generated half of every screen, and a
                // baseline older than that sees its own output as a change and
                // restarts once for nothing.
                sentinel.moved()?
                let status: int = launch_until(
                    project, built.binary, arguments,
                    fn() -> bool {
                        match sentinel.moved() {
                            ok(changed) => { return changed }
                            err(problem) => { return false }
                        }
                    })?
                if status == restarted_status() {
                    build_again = true
                } else {
                    // The program finished on its own terms. Wait for an edit
                    // rather than restarting it, because relaunching something
                    // a person just quit is a loop they cannot get out of.
                    io.eprintln("exited {status} — waiting for a change")
                }
            }
            err(problem) => {
                io.eprintln("cortado: {problem.msg}")
                io.eprintln("waiting for a change")
            }
        }
        if !build_again {
            if !wait_for_change(sentinel)? { return ok(0) }
        }
        io.eprintln("")
        io.eprintln("something changed — building again")
    }
    return ok(0)
}

/// Block until something moves. Always true today; the shape is here because
/// a watch that can be told to stop is the next thing this wants.
fn wait_for_change(sentinel: Sentinel) -> Result<bool> {
    var spins: int = 0
    for spins < 100000000 {
        if sentinel.moved()? { return ok(true) }
        time.sleep_millis(tick_ms())
        spins += 1
    }
    return ok(false)
}
