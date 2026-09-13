// scaffold.b — `cortado init`, and what a cortado project looks like.
//
// The structure is **screens and services**, which is what cortado's own
// pieces already are rather than a pattern imported from somewhere else:
//
//     myapp/
//     ├── beans.pot        the module and what it depends on
//     ├── cortado.pot      the application: name, identity, profiles
//     ├── main.b           four lines
//     ├── screens/         one .bx per screen
//     ├── components/      .bx parts a screen reuses
//     ├── services/        plain .b — injected, no UI, testable alone
//     ├── models/          plain data
//     └── generated/       the .b half of every .bx, mirroring its folder
//
// **There is no ViewModel folder, and that is a decision.** A `.bx` file is
// markup on top and a `partial class` underneath — the view and the object
// holding its state and commands, in one file, kept in step by the compiler.
// A separate view-model class could not be bound to: cortado has no binding
// engine, so it would forward every property by hand and call
// `request_render()` itself, which is ceremony and not separation. What a view
// model is *for* — logic you can exercise without a screen — is what
// `services/` is, and a service is testable with no window at all.
//
// **`generated/` is checked in.** A clone then builds with plain `beansc`, and
// `cortado check --drift` is what makes that safe: a generated file that no
// longer matches its markup fails a gate instead of shipping.

package cli

import std.fs
import std.path
import std.io

/// Where cortado and barista are, as `require path` rows would write them.
pub class Neighbours {
    pub cortado: string = ""
    pub barista: string = ""

    pub fn init(cortado: string, barista: string) {
        self.cortado = cortado
        self.barista = barista
    }
}

/// Find a checkout of `wanted` at or above `from`, as a relative path.
///
/// Walks up level by level and looks for the module both beside that level and
/// under a `community-libs/` in it, which is the two shapes this ecosystem's
/// checkouts actually take. The answer is built from the number of levels
/// climbed, so it is exact rather than a path subtraction that has to guess
/// about symlinks.
fn find_beside(from: string, wanted: string) -> Option<string> {
    var here: string = from
    if here == "" { here = "." }
    var up: string = ""
    var depth: int = 0
    for depth < 32 {
        for shape: string in [wanted, path.join("community-libs", wanted)] {
            let candidate: string = path.join(here, shape)
            if fs.exists(path.join(candidate, "beans.pot")) {
                if up == "" { return some(shape) }
                return some("{up}{shape}")
            }
        }
        var parent: string = path.parent(here)
        if parent == "" {
            if here == "." { parent = ".." } else { break }
        }
        if parent == here { break }
        here = parent
        up = "{up}../"
        depth += 1
    }
    return none
}

/// The two modules a scaffolded project depends on, found or refused.
///
/// **Refused rather than guessed.** A `require` row naming a directory that is
/// not there fails at the first build with a message about a manifest, which
/// is a worse place to learn it than here. Git rows are the other answer and
/// they are not written yet: cortado has no published tag to pin, and a row
/// pinning `HEAD` of an unpublished repository is a row that resolves
/// differently every week. When there is a release, `--git <ref>` is the flag
/// that writes it, and it belongs in the same change as the release.
pub fn find_neighbours(project_dir: string, given: string) -> Result<Neighbours> {
    if given != "" {
        if !fs.exists(path.join(given, "beans.pot")) {
            return err("--cortado {given} has no beans.pot in it", "no_cortado")
        }
        let sibling: string = path.join(given, "../barista")
        return ok(new Neighbours(given, sibling))
    }
    let parent: string = path.parent(project_dir)
    var found_cortado: string = ""
    match find_beside(parent, "cortado") {
        some(where) => { found_cortado = where }
        none => {
            return err(
                "cannot find a cortado checkout above {project_dir} — pass --cortado <path>",
                "no_cortado")
        }
    }
    var found_barista: string = ""
    match find_beside(parent, "barista") {
        some(where) => { found_barista = where }
        none => {
            return err(
                "cannot find a barista checkout above {project_dir} — pass --cortado <path> and put barista beside it",
                "no_barista")
        }
    }
    return ok(new Neighbours(found_cortado, found_barista))
}

fn write_file(root: string, relative: string, text: string) -> Result<bool> {
    let target: string = path.join(root, relative)
    let folder: string = path.parent(target)
    if folder != "" {
        match Dir.create_all(folder) {
            ok(_) => {}
            err(problem) => {
                return err("cannot make {folder}: {problem.msg}", "init")
            }
        }
    }
    fs.write(target, text)?
    io.eprintln("  {relative}")
    return ok(true)
}

/// A name that can be a Beans module and a directory at once.
pub fn legal_project_name(name: string) -> bool {
    if name == "" { return false }
    var index: int = 0
    for index < name.len() {
        let byte: int = name.byte_at(index)
        let lower: bool = byte >= 97 && byte <= 122
        let digit: bool = byte >= 48 && byte <= 57
        let underscore: bool = byte == 95
        if index == 0 && !lower { return false }
        if !lower && !digit && !underscore { return false }
        index += 1
    }
    return !name.ends_with("_")
}

/// `myapp` -> `Myapp`, for the window title and the bundle name.
fn titled(name: string) -> string {
    if name == "" { return name }
    return "{name.slice(0, 1).to_upper()}{name.slice(1, name.len())}"
}

/// The file bodies.
///
/// They are raw literals: nothing in a raw literal is an escape and nothing in
/// it opens an interpolation, so each template below is byte for byte the file
/// it writes — braces, quotes, `@` and all. The three placeholders are
/// substituted afterwards. Writing these as ordinary interpolated strings
/// would mean escaping every `{` in generated Beans code, which is most of
/// them, and the template would stop looking like its output.
fn filled(template: string, name: string, shown: string) -> string {
    return template.replace("__NAME__", name).replace("__SHOWN__", shown)
}

fn template_beans_pot() -> string {
    return r##"module __NAME__
kind application

# cortado is the framework; cortado_app is the composition root that wires
# barista onto it; barista is here because a scan finds this project's own
# `@barista.service` classes and the row is what puts the container in reach.
require path "__CORTADO__"
require path "__CORTADO__/app"
require path "__BARISTA__"
"##
}

fn template_cortado_pot() -> string {
    return r##"# The application, as against the module. `beans.pot` cannot hold any of this:
# the compiler refuses a row it does not know, which is the right rule and the
# reason this file exists beside it.
name       __SHOWN__
identifier com.example.__NAME__
version    0.1.0

# The folders holding markup. Every `.bx` under one is regenerated on every
# build; a `.bx` outside all of them is an error, because a screen nothing
# regenerates is a screen that still renders last week's design.
markup     screens
markup     components

profile debug
    out    build/debug
profile release
    out    build/release
    lto    true

# Keys the bundle's Info.plist carries. On macOS a privacy-gated framework
# touched without its usage description does not fail — it ends the process —
# so a feature that needs one names it here.
# plist NSCameraUsageDescription "to scan a receipt"
"##
}

fn template_main() -> string {
    return r##"// __SHOWN__ — a cortado application.
//
//     cortado run                  build and run, Debug
//     cortado build -c Release     optimised, into build/release/
//     cortado run -- --dump        the widget tree, headless, then exit
//
// The window's size and title are on `Home` itself, as `@window`. The nine
// steps between `main` and a screen on the display — the container, the
// application, the window, the mount, the render loop, and taking all of it
// back down in the right order — are `cortado_app.run_main`.
package main

import cortado_app
import {Home} from __NAME__.generated.screens

// A `@barista.service` in a package nothing imports is not in the executable,
// and so is never registered: cortado has no registry of services and
// `reflect.types()` is the registry. The screen imports `Menu` too, for its
// `@inject` field, so this row is belt and braces — but the first service that
// nothing names by type will need exactly it.
import {Menu} from __NAME__.services

fn main() {
    var options: cortado_app.AppOptions = new cortado_app.AppOptions()
    cortado_app.run_main<Home>(options)
}
"##
}

fn template_model() -> string {
    return r##"// Plain data. No framework, no platform, no container.
package models

pub class Drink {
    pub name: string = "flat white"
    pub shots: int = 1

    pub fn init() {}
}
"##
}

fn template_service() -> string {
    return r##"// What a drink costs. Registered by the scan, injected where it is needed,
// and exercisable with no window — which is what a view model would have been
// for, in a framework that needed one.
package services

import barista
import {Drink} from __NAME__.models

@barista.service(lifetime: barista.ServiceLifetime.singleton)
pub class Menu {
    pub fn init() {}

    pub fn price(drink: Drink) -> int {
        var each: int = 300
        if drink.name == "flat white" { each = 380 }
        if drink.name == "espresso" { each = 260 }
        return each + (drink.shots - 1) * 60
    }

    pub fn next(name: string) -> string {
        if name == "flat white" { return "espresso" }
        if name == "espresso" { return "cortado" }
        return "flat white"
    }
}
"##
}

fn template_badge() -> string {
    return r##"<Label font_size={13}>$self.words</Label>
<beans>
package components

import cortado.component
import {view, param} from cortado.annotations

// A part a screen reuses. It generates into `generated/components/`, which is
// the package `components`, so the screen that uses it needs one import line
// and nothing else.
@view
pub partial class Badge extends component.Component {
    @param pub words: string = ""

    pub fn init() { super.init() }
}
</beans>
"##
}

fn template_home() -> string {
    return r##"<VStack spacing={14} padding={24} align="stretch">
  <Label font_size={17}>$self.drink.name</Label>
  <Label>$self.drink.shots × $self.total()p</Label>

  <Badge words="tap Change for another drink" />

  <HStack spacing={10} justify="end">
    <Button enabled={self.drink.shots < 4} on:click={fn(e: UiEvent) { self.add_shot() }}>
      Another shot
    </Button>
    <Button on:click={fn(e: UiEvent) { self.change_drink() }}>
      Change
    </Button>
  </HStack>
</VStack>
<beans>
package screens

import cortado.component
import {view, inject, window} from cortado.annotations
import {Badge} from __NAME__.generated.components
import {Menu} from __NAME__.services
import {Drink} from __NAME__.models

// `@window` is where this application's window size and title live — beside
// the screen they describe, and readable by a tool without running it.
@view
@window(title: "__SHOWN__", width: 420.0, height: 260.0)
pub partial class Home extends component.Component {
    @inject pub menu: Menu = new Menu()
    pub drink: Drink = new Drink()

    pub fn init() { super.init() }

    pub fn total() -> int {
        return self.menu.price(self.drink)
    }

    pub fn add_shot() {
        self.drink.shots = self.drink.shots + 1
        self.request_render()
    }

    pub fn change_drink() {
        self.drink.name = self.menu.next(self.drink.name)
        self.drink.shots = 1
        self.request_render()
    }
}
</beans>
"##
}

/// Write a whole project into `directory`.
pub fn scaffold(directory: string, name: string, cortado_path: string) -> Result<bool> {
    if !legal_project_name(name) {
        return err(
            "'{name}' cannot be a module name — lowercase letters, digits and underscores, starting with a letter",
            "init")
    }
    if fs.exists(path.join(directory, "beans.pot")) {
        return err("{directory}/beans.pot already exists", "init")
    }
    let near: Neighbours = find_neighbours(directory, cortado_path)?
    let shown: string = titled(name)

    io.eprintln("creating {directory}")
    let manifest: string =
        filled(template_beans_pot(), name, shown)
            .replace("__CORTADO__", near.cortado)
            .replace("__BARISTA__", near.barista)
    write_file(directory, "beans.pot", manifest)?
    write_file(directory, "cortado.pot",
               filled(template_cortado_pot(), name, shown))?
    write_file(directory, ".gitignore", "build/\n")?
    write_file(directory, "main.b", filled(template_main(), name, shown))?
    write_file(directory, "models/drink.b",
               filled(template_model(), name, shown))?
    write_file(directory, "services/menu.b",
               filled(template_service(), name, shown))?
    write_file(directory, "components/badge.bx",
               filled(template_badge(), name, shown))?
    write_file(directory, "screens/home.bx",
               filled(template_home(), name, shown))?

    var options: GenerateOptions = new GenerateOptions()
    let made: int = generate([path.join(directory, "screens"),
                              path.join(directory, "components")], options)?
    io.eprintln("  generated/ ({made} file(s))")
    io.eprintln("")
    io.eprintln("{shown} is ready. Next:")
    io.eprintln("    cd {directory} && cortado run")
    return ok(true)
}
