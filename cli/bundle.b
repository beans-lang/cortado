// bundle.b — `cortado publish`: a Release build, wrapped so it can be shipped.
//
// A bare Mach-O binary runs and shows a window, which is why cortado's
// examples work without any of this. What it does not get is a name in the
// Dock, a name in the menu bar, a place in Launch Services, an icon, a
// signature — or a usage description, and that last one is not cosmetic: macOS
// does not refuse a program that touches a privacy-gated framework without
// one, it **ends the process**, on a later turn of the run loop, with nothing
// on stderr. `cortado.device` refuses to ask without a bundle for exactly that
// reason, so the `plist` rows in `cortado.pot` are what turn `unavailable`
// into a real answer.
//
// **This is the implementation, and `tools/bundle.sh` calls it.** There was a
// version of this plan where the script stayed as it was and this was written
// beside it, and two programs writing one Info.plist is two plists that agree
// until somebody adds a key to one.
//
// **Every key is read back out of the finished bundle**, with `plutil
// -extract`, which is how macOS reads it. Not "the file contains it" and not
// "the file lints": the first version of the shell script wrote the usage
// descriptions *after* `</plist>`, `plutil -lint` called the file OK because a
// plist parser stops at the closing tag, the app launched, the bundle was
// recognised, and every usage description was silently missing.

package cli

import std.fs
import std.path
import std.io
import std.os
import std.target
import std.process

/// The first macOS with Apple silicon, which is the oldest cortado's host
/// builds for.
fn minimum_system() -> string {
    return "11.0"
}

/// XML text, with the five characters that are not text in XML spelled out.
///
/// `tools/bundle.sh` did not do this, and a usage description containing an
/// ampersand — "to scan a receipt & file it" — wrote a plist that `plutil`
/// refuses, from a manifest row that looked perfectly reasonable.
fn xml_text(value: string) -> string {
    return value.replace("&", "&amp;").replace("<", "&lt;")
                .replace(">", "&gt;").replace("\"", "&quot;")
                .replace("'", "&apos;")
}

fn plist_row(key: string, value: string) -> string {
    return "  <key>{xml_text(key)}</key><string>{xml_text(value)}</string>"
}

/// The Info.plist for an application.
pub fn info_plist(manifest: AppManifest, name: string, identifier: string) -> string {
    var rows: List<string> = []
    rows.push(r##"<?xml version="1.0" encoding="UTF-8"?>"##)
    rows.push(r##"<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">"##)
    rows.push(r##"<plist version="1.0">"##)
    rows.push("<dict>")
    rows.push(plist_row("CFBundleName", name))
    rows.push(plist_row("CFBundleDisplayName", name))
    rows.push(plist_row("CFBundleExecutable", name))
    rows.push(plist_row("CFBundleIdentifier", identifier))
    rows.push(plist_row("CFBundleVersion", manifest.version))
    rows.push(plist_row("CFBundleShortVersionString", manifest.version))
    rows.push(plist_row("CFBundlePackageType", "APPL"))
    rows.push(plist_row("CFBundleInfoDictionaryVersion", "6.0"))
    rows.push(plist_row("LSMinimumSystemVersion", minimum_system()))
    rows.push("  <key>NSHighResolutionCapable</key><true/>")
    if manifest.icon != "" {
        rows.push(plist_row("CFBundleIconFile",
                            path.stem(path.name(manifest.icon))))
    }
    // Inside the dict — see the note at the top of this file about the version
    // that put them after `</plist>` and lint-ed clean.
    for entry: PlistEntry in manifest.plist {
        rows.push(plist_row(entry.key, entry.value))
    }
    rows.push("</dict>")
    rows.push("</plist>")
    rows.push("")
    return rows.join("\n")
}

fn tool(program: string, arguments: List<string>) -> Result<process.Output> {
    var command: process.Command = new process.Command(program)
    for one: string in arguments { command.arg(one) }
    return command.run()
}

/// Wrap a built binary as a macOS `.app`.
///
/// Takes the manifest and the paths rather than a `Project`, because the other
/// caller is a loose binary that is not one — `tools/bundle.sh` wraps a built
/// example, and it goes through here so there is one program writing an
/// Info.plist rather than two that agree until somebody adds a key to one.
pub fn bundle_macos(root: string, manifest: AppManifest, name: string, binary: string, out_dir: string) -> Result<string> {
    if manifest.identifier == "" {
        return err(
            "publish needs a bundle identifier — add 'identifier com.example.{name.to_lower()}' to cortado.pot",
            "publish")
    }
    let source: string = path.join(root, binary)
    if !fs.exists(source) {
        return err("{binary} is not there — build it first", "publish")
    }

    let app: string = path.join(path.join(root, out_dir), "{name}.app")
    if Dir.exists(app) { Dir.remove_all(app)? }
    let macos_dir: string = path.join(path.join(app, "Contents"), "MacOS")
    let resources: string = path.join(path.join(app, "Contents"), "Resources")
    Dir.create_all(macos_dir)?
    Dir.create_all(resources)?

    let placed: string = path.join(macos_dir, name)
    fs.copy(source, placed)?
    // A copied binary is not executable unless it is made so, and a bundle
    // whose executable cannot be run fails at launch with a Finder dialog
    // that says nothing about why.
    tool("chmod", ["+x", placed])?

    let plist: string = path.join(path.join(app, "Contents"), "Info.plist")
    fs.write(plist, info_plist(manifest, name, manifest.identifier))?

    if manifest.icon != "" {
        let icon: string = path.join(root, manifest.icon)
        if !fs.exists(icon) {
            return err(
                "cortado.pot says 'icon {manifest.icon}', and it is not there",
                "publish")
        }
        fs.copy(icon, path.join(resources, path.name(manifest.icon)))?
    }

    // Read every declared key back the way macOS reads it.
    for entry: PlistEntry in manifest.plist {
        let read: process.Output =
            tool("plutil", ["-extract", entry.key, "raw", "-o", "-", plist])?
        if !read.succeeded() {
            return err(
                "{entry.key} is not readable from the Info.plist it was just written into — macOS would show no prompt and cortado would answer 'unavailable' with nothing to explain it",
                "publish")
        }
    }
    let linted: process.Output = tool("plutil", ["-lint", plist])?
    if !linted.succeeded() {
        return err("the Info.plist is malformed: {linted.stdout_text()}",
                   "publish")
    }

    // Ad-hoc by default: enough to run locally on Apple silicon, and not
    // enough to distribute — that needs a Developer ID and notarisation, which
    // need an account. So this does the part that can be automated and says
    // which part it did not.
    var identity: string = "-"
    match os.env("CORTADO_SIGN_IDENTITY") {
        some(named) => { if named != "" { identity = named } }
        none => {}
    }
    let signed: process.Output =
        tool("codesign", ["--force", "--sign", identity, "--timestamp=none", app])?
    if !signed.succeeded() {
        return err("codesign failed with identity '{identity}': {signed.stderr_text()}",
                   "publish")
    }
    let verified: process.Output = tool("codesign", ["--verify", "--strict", app])?
    if !verified.succeeded() {
        return err("the signature does not verify: {verified.stderr_text()}",
                   "publish")
    }
    return ok(app)
}

/// Wrap a binary that is not a project: `tools/bundle.sh`'s job.
///
/// The bundle is written beside the binary, which is where that script has
/// always put it and what every caller of it already expects.
pub fn publish_binary(binary: string, manifest: AppManifest, name: string) -> Result<bool> {
    if target.os() != "macos" {
        return err(
            "publish only knows how to make a macOS .app — a Windows manifest and a Linux .desktop file are not written",
            "unsupported")
    }
    // Every path the caller gave is relative to where they are standing, so
    // that is the root; the bundle goes beside the binary, which is where this
    // has always put it.
    var out_dir: string = path.parent(binary)
    if out_dir == "" { out_dir = "." }
    let app: string = bundle_macos(".", manifest, name, binary, out_dir)?
    io.eprintln("built {app}")
    io.eprintln("  identifier {manifest.identifier}, version {manifest.version}")
    return ok(true)
}

/// A Release build, then a bundle for this platform.
pub fn publish_project(project: Project, profile: Profile) -> Result<bool> {
    if target.os() != "macos" {
        // Windows wants an .exe beside a manifest and Linux wants a .desktop
        // file. Both are real work and neither is written; saying so is better
        // than producing a directory that looks like a bundle and is not one.
        return err(
            "publish only knows how to make a macOS .app — a Windows manifest and a Linux .desktop file are not written",
            "unsupported")
    }
    let built: Built = build_project(project, profile)?
    io.eprintln("built {built.binary} ({built.profile})")
    let app: string = bundle_macos(project.root, project.manifest,
                                   project.binary_name(), built.binary,
                                   profile.out)?
    io.eprintln("built {app}")
    io.eprintln("  identifier {project.manifest.identifier}, version {project.manifest.version}")
    io.eprintln("  signed ad-hoc — enough to run here, not enough to distribute:")
    io.eprintln("  that needs a Developer ID and notarisation.")
    return ok(true)
}
