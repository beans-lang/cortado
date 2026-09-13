// manifest.b — `cortado.pot`, the project's own manifest.
//
// `beans.pot` says what a module is and what it depends on. It cannot say what
// an *application* is, because the compiler refuses a row it does not know
// (`unknown beans.pot line:` in beans/src/module.b) — so a bundle identifier,
// an icon, a usage description and a build profile have nowhere to live in it.
// This is that file, beside it, in the same shape:
//
//     name       Cask
//     identifier com.example.cask
//     version    0.1.0
//     icon       assets/cask.icns
//
//     markup     screens
//     markup     components
//
//     plist NSCameraUsageDescription "to scan a receipt"
//
//     profile debug
//         out    build/debug
//     profile release
//         out    build/release
//         lto    true
//         bundle true
//
// Three decisions are worth the sentence each.
//
// **An unrecognised row is refused, not ignored.** That is `beans.pot`'s rule
// and it is the right one: a manifest that silently drops `identfier` gives you
// an application signed under the wrong identity and nothing to read about it.
// The refusal names the line and the word.
//
// **The tokenizer is `beans.pot`'s, byte for byte.** Whitespace separates
// words, `"` quotes one, `\` escapes inside a quote, and `#` or `//` outside a
// quote ends the line. A usage description is a sentence with spaces in it and
// a path may contain a `#`, so neither could be written without this.
//
// **Indentation means nothing.** A `profile` row opens a block and the rows
// that only make sense inside one — `out`, `lto`, `bundle`, `target`, `cpu`,
// `features` — belong to the profile above them. The indentation in the
// example is for a person; a parser that depended on it would refuse a file
// somebody's editor re-tabbed.

package cli

import std.fs
import std.path

/// The two profiles, and only two.
///
/// dotnet ships `Debug` and `Release` and lets a project add a third; cortado
/// ships the two and refuses the third *by name*, because a third profile is
/// only meaningful once something can vary that these two cannot express, and
/// nothing can yet — `beansc` has `--debug`, `--release` and `--lto` and that
/// is the whole surface. When a project needs one, what it needs is a
/// `optimize` row saying which flag the profile passes, and that is the change
/// to make then rather than an empty mechanism to carry until.
pub fn profile_names() -> List<string> {
    return ["debug", "release"]
}

/// One build configuration.
pub class Profile {
    /// The profile's own name, `debug` or `release`.
    pub name: string = ""
    /// The directory the binary is written into.
    pub out: string = ""
    /// Link-time optimization. `beansc` already refuses to combine it with a
    /// debug build, so this is ignored rather than refused under `debug`.
    pub lto: bool = false
    /// A cross-compilation triple, or empty for this machine.
    pub target: string = ""
    pub cpu: string = ""
    pub features: string = ""
    /// Whether `cortado publish` is implied by a build of this profile.
    pub bundle: bool = false

    pub fn init(name: string, out: string) {
        self.name = name
        self.out = out
    }

    /// True for the profile that asks `beansc` for `--release`.
    pub fn is_release() -> bool {
        return self.name == "release"
    }
}

/// One `plist` row: a key the bundle's `Info.plist` carries.
pub class PlistEntry {
    pub key: string = ""
    pub value: string = ""

    pub fn init(key: string, value: string) {
        self.key = key
        self.value = value
    }
}

/// What `cortado.pot` said.
pub class AppManifest {
    /// The application's name — what the bundle is called and what the binary
    /// is named. Empty means: take the `module` line from `beans.pot`.
    pub name: string = ""
    /// The bundle identifier. Only `publish` needs one.
    pub identifier: string = ""
    pub version: string = "0.1.0"
    pub icon: string = ""
    /// The folders holding `.bx` markup, relative to the project root.
    pub markup: List<string> = []
    pub plist: List<PlistEntry> = []
    pub debug: Profile = new Profile("debug", "build/debug")
    pub release: Profile = new Profile("release", "build/release")
    /// True when a `cortado.pot` was actually read. A project without one
    /// still builds — every field above has an answer — but `publish` needs
    /// an identifier and says so.
    pub present: bool = false

    pub fn init() {}

    /// The profile by name, or a refusal naming the two there are.
    pub fn profile(named: string) -> Result<Profile> {
        if named == "debug" { return ok(self.debug) }
        if named == "release" { return ok(self.release) }
        return err(
            "{named} is not a configuration — cortado has debug and release",
            "profile")
    }
}

/// Tokenize one line the way `beans.pot` is tokenized.
///
/// Comments only start outside quotes, so a usage description may contain a
/// `#` and a path may contain a `//`. An unterminated quote collapses the line
/// to one sentinel word, which the caller turns into a diagnostic that names
/// the line — the same shape the compiler's own manifest reader uses.
fn manifest_words(line: string) -> List<string> {
    var words: List<string> = []
    var word: string = ""
    var started: bool = false
    var quoted: bool = false
    var escaping: bool = false
    var index: int = 0
    for index < line.len() {
        let byte: int = line.byte_at(index)
        if quoted {
            if escaping {
                word = "{word}{line.slice(index, index + 1)}"
                escaping = false
            } else if byte == 92 {
                escaping = true
            } else if byte == 34 {
                quoted = false
            } else {
                word = "{word}{line.slice(index, index + 1)}"
            }
            index += 1
            continue
        }
        if byte == 34 {
            quoted = true
            started = true
            index += 1
            continue
        }
        let slash_comment: bool =
            byte == 47 && index + 1 < line.len() &&
            line.byte_at(index + 1) == 47
        if byte == 35 || slash_comment {
            break
        }
        if byte == 32 || byte == 9 || byte == 13 {
            if started {
                words.push(word)
                word = ""
                started = false
            }
        } else {
            word = "{word}{line.slice(index, index + 1)}"
            started = true
        }
        index += 1
    }
    if started { words.push(word) }
    if quoted || escaping {
        words = ["$manifest-error:unterminated-quote$"]
    }
    return move words
}

/// A `true`/`false` row, refused rather than guessed.
fn read_flag(file: string, line_number: int, row: string,
             written: string) -> Result<bool> {
    if written == "true" { return ok(true) }
    if written == "false" { return ok(false) }
    return err(
        "{file}:{line_number}: {row} needs true or false, not '{written}'",
        "manifest")
}

/// Parse the text of a `cortado.pot`.
///
/// Separated from reading the file so the gate can hand it a string and so a
/// refusal can be tested without a temporary directory.
pub fn parse_manifest(file: string, text: string) -> Result<AppManifest> {
    var manifest: AppManifest = new AppManifest()
    manifest.present = true
    var open_profile: string = ""
    var line_number: int = 0
    for line: string in text.lines() {
        line_number += 1
        let words: List<string> = manifest_words(line)
        if words.is_empty() { continue }
        if words.len() == 1 &&
           words[0] == "$manifest-error:unterminated-quote$" {
            return err("{file}:{line_number}: unterminated quoted string",
                       "manifest")
        }
        let row: string = words[0]

        if row == "profile" {
            if words.len() != 2 {
                return err("{file}:{line_number}: profile needs a name",
                           "manifest")
            }
            if words[1] != "debug" && words[1] != "release" {
                return err(
                    "{file}:{line_number}: '{words[1]}' is not a configuration — cortado has debug and release",
                    "manifest")
            }
            open_profile = words[1]
            continue
        }

        // The rows that only mean something inside a profile. Written above
        // the first `profile` line they are a mistake with an obvious shape,
        // so say which one it is rather than refusing the word itself.
        if row == "out" || row == "lto" || row == "bundle" ||
           row == "target" || row == "cpu" || row == "features" {
            if open_profile == "" {
                return err(
                    "{file}:{line_number}: {row} belongs to a profile — put it under 'profile debug' or 'profile release'",
                    "manifest")
            }
            if words.len() != 2 {
                return err("{file}:{line_number}: {row} needs exactly one value",
                           "manifest")
            }
            var into: Profile = manifest.debug
            if open_profile == "release" { into = manifest.release }
            if row == "out" { into.out = words[1] }
            else if row == "target" { into.target = words[1] }
            else if row == "cpu" { into.cpu = words[1] }
            else if row == "features" { into.features = words[1] }
            else if row == "lto" {
                into.lto = read_flag(file, line_number, row, words[1])?
            } else {
                into.bundle = read_flag(file, line_number, row, words[1])?
            }
            continue
        }

        // Everything below is a top-level row, and a top-level row closes the
        // profile above it — so a `name` written after a profile block is the
        // application's name and not a profile row nobody declared.
        open_profile = ""

        if row == "name" || row == "identifier" || row == "version" ||
           row == "icon" {
            if words.len() != 2 {
                return err("{file}:{line_number}: {row} needs exactly one value",
                           "manifest")
            }
            if row == "name" { manifest.name = words[1] }
            else if row == "identifier" { manifest.identifier = words[1] }
            else if row == "version" { manifest.version = words[1] }
            else { manifest.icon = words[1] }
            continue
        }
        if row == "markup" {
            if words.len() != 2 {
                return err(
                    "{file}:{line_number}: markup needs exactly one directory",
                    "manifest")
            }
            for already: string in manifest.markup {
                if already == words[1] {
                    return err(
                        "{file}:{line_number}: markup {words[1]} is written twice",
                        "manifest")
                }
            }
            manifest.markup.push(words[1])
            continue
        }
        if row == "plist" {
            if words.len() != 3 {
                return err(
                    "{file}:{line_number}: plist needs a key and a value",
                    "manifest")
            }
            for already: PlistEntry in manifest.plist {
                if already.key == words[1] {
                    return err(
                        "{file}:{line_number}: plist key {words[1]} is written twice",
                        "manifest")
                }
            }
            manifest.plist.push(new PlistEntry(words[1], words[2]))
            continue
        }
        return err("{file}:{line_number}: unknown cortado.pot row: {row}",
                   "manifest")
    }
    return ok(manifest)
}

/// Read `cortado.pot` from a project root.
///
/// A project without one is not an error: every field has a default, so an
/// application that needs no bundle identity never has to write the file. The
/// commands that do need one say which row is missing.
pub fn read_manifest(root: string) -> Result<AppManifest> {
    let file: string = path.join(root, "cortado.pot")
    if !fs.exists(file) {
        var absent: AppManifest = new AppManifest()
        return ok(absent)
    }
    let text: string = fs.read(file)?
    return parse_manifest(file, text)
}
