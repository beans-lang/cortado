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

/// Where a cortado checkout is, as a `require path` row would write it.
pub class Neighbours {
    pub cortado: string = ""

    pub fn init(cortado: string) {
        self.cortado = cortado
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

/// The cortado checkout a scaffolded project builds against.
/// Only `--cortado <path>` reaches this; the default pins the releases.
pub fn find_neighbours(project_dir: string, given: string) -> Result<Neighbours> {
    if given != "" {
        if !fs.exists(path.join(given, "beans.pot")) {
            return err("--cortado {given} has no beans.pot in it", "no_cortado")
        }
        return ok(new Neighbours(given))
    }
    let parent: string = path.parent(project_dir)
    match find_beside(parent, "cortado") {
        some(where) => { return ok(new Neighbours(where)) }
        none => {
            return err(
                "cannot find a cortado checkout above {project_dir} — pass --cortado <path>",
                "no_cortado")
        }
    }
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
/// They are raw literals: nothing in one is an escape and nothing opens an
/// interpolation, so each template is byte for byte the file it writes.
/// `filled` and `spelled` substitute the `__PLACEHOLDER__` words afterwards.
fn filled(template: string, name: string, shown: string) -> string {
    return template.replace("__NAME__", name).replace("__SHOWN__", shown)
}

/// The import paths a scaffolded project writes, for the spelling it pins.
/// The binding is the module name either way, so only these lines differ.
fn spelled(template: string, git: bool) -> string {
    var app: string = "cortado_app"
    var component: string = "cortado.component"
    var annotations: string = "cortado.annotations"
    // barista is always the release: cortado's own manifest pins it, and one
    // module reached two ways is a refusal.
    let barista: string = "github.com/beans-lang/barista"
    if git {
        app = "github.com/beans-lang/cortado/app"
        component = "github.com/beans-lang/cortado/component"
        annotations = "github.com/beans-lang/cortado/annotations"
    }
    return template.replace("__CORTADO_APP__", app)
                   .replace("__CORTADO_COMPONENT__", component)
                   .replace("__CORTADO_ANNOTATIONS__", annotations)
                   .replace("__BARISTA__", barista)
}

fn template_beans_pot() -> string {
    return r##"module __NAME__
kind application

# cortado is the framework and carries `cortado_app`, the composition root that
# wires barista onto it; barista is named here too because the scan that finds
# this project's own `@barista.service` classes needs it in reach.
__REQUIRES__
"##
}

/// The released cortado and barista this CLI scaffolds against. `test.sh`
/// holds `cortado_release` against `cortado.version()`, so a stale pin is red.
pub fn cortado_release() -> string { return "v0.1.1" }
pub fn barista_release() -> string { return "v0.1.1" }

fn git_requires() -> string {
    return "require github.com/beans-lang/cortado {cortado_release()}\nrequire github.com/beans-lang/barista {barista_release()}"
}

fn path_requires(near: Neighbours) -> string {
    return "require path \"{near.cortado}\"\nrequire path \"{near.cortado}/app\"\nrequire github.com/beans-lang/barista {barista_release()}"
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

import __CORTADO_APP__
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

import __BARISTA__
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

import __CORTADO_COMPONENT__
import {view, param} from __CORTADO_ANNOTATIONS__

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

import __CORTADO_COMPONENT__
import {view, inject, window} from __CORTADO_ANNOTATIONS__
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
    // A project pins the published releases. `--cortado <path>` is the other
    // answer, for working on cortado itself against an uncommitted checkout.
    let git: bool = cortado_path == ""
    var requires: string = git_requires()
    if !git {
        requires = path_requires(find_neighbours(directory, cortado_path)?)
    }
    let shown: string = titled(name)

    io.eprintln("creating {directory}")
    let manifest: string =
        filled(template_beans_pot(), name, shown)
            .replace("__REQUIRES__", requires)
    write_file(directory, "beans.pot", manifest)?
    write_file(directory, "cortado.pot",
               filled(template_cortado_pot(), name, shown))?
    write_file(directory, ".gitignore", "build/\n")?
    write_file(directory, "main.b",
               spelled(filled(template_main(), name, shown), git))?
    write_file(directory, "models/drink.b",
               filled(template_model(), name, shown))?
    write_file(directory, "services/menu.b",
               spelled(filled(template_service(), name, shown), git))?
    write_file(directory, "components/badge.bx",
               spelled(filled(template_badge(), name, shown), git))?
    write_file(directory, "screens/home.bx",
               spelled(filled(template_home(), name, shown), git))?

    var options: GenerateOptions = new GenerateOptions()
    let made: int = generate([path.join(directory, "screens"),
                              path.join(directory, "components")], options)?
    io.eprintln("  generated/ ({made} file(s))")
    io.eprintln("")
    io.eprintln("{shown} is ready. Next:")
    io.eprintln("    cd {directory} && cortado run")
    return ok(true)
}
