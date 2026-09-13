// cortado-bx — the markup compiler's command line, which is now an alias.
//
// **Why this is under `examples/` and not at the module root.** cortado is a
// `kind library` module, and a library may only hold a program entry under
// `examples/` or `tests/`. A root-level `package main` file is refused twice
// over — one directory is one package, and a library root declares a normal
// package name rather than `main`. So this is not a demo; it is where the
// binary's entry is allowed to live.
//
// Everything it does is `cortado generate` (`cli/generate.b`). It is kept
// because the editors' vocabulary, the drift gate and a good deal of writing
// all name it, and because compiling markup without building an application is
// a reasonable thing to want. What it is not is a second implementation of the
// directory walk or the mirror rule — a second one is how two tools come to
// disagree about what is in a folder, and the answer that comes up one short
// is a stale generated file that still compiles and says nothing.
//
//     beansc build examples/cortado_bx.b -o build/cortado-bx
//     build/cortado-bx build screens/home.bx
package main

import std.os
import cortado.cli

fn main() {
    let status: int = cli.bx_main_with(os.args())
    if status != 0 { os.exit(status) }
}
