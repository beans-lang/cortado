// cortado — the project command line.
//
// **Why this is under `examples/` and not at the module root.** cortado is a
// `kind library` module, and a library may only hold a program entry under
// `examples/` or `tests/`. A root-level `package main` file is refused twice
// over — one directory is one package, and a library root declares a normal
// package name rather than `main`. So this is not a demo; it is where the
// binary's entry is allowed to live.
//
// It imports `cortado.cli` and nothing else of cortado's, and `cortado.cli`
// imports `cortado.bx`, `std.fs`, `std.process` and `std.poll`. None of that
// reaches `cortado.host`, so this tool builds and runs on every operating
// system — including the ones whose host has not been written — and an
// application that ships a screen links none of it.
//
//     beansc build examples/cortado_cli.b -o build/cortado
//     build/cortado init myapp && cd myapp && ../build/cortado run
package main

import cortado.cli

fn main() {
    cli.run_cli()
}
