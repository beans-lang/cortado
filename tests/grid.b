// Columns a grid works out from the room it is given.
//
// `<Grid>` could only ever be one column: the engine had `Track.fixed`,
// `Track.auto` and `Track.fraction` from the start and markup could name none
// of them. `columns` names them, and `min_column` is the web's
// `repeat(auto-fit, minmax(min, 1fr))` — the one thing that makes a shelf
// reflow with no breakpoint written anywhere.
//
// Three widths, because two would show a shelf changing and three show it
// changing twice. Solved against `TableMeasure`; nothing here needs a display.
package main

import cortado.component
import cortado.layout
import cortado.geometry
import std.io

// Every tile measures 100 x 20, so a frame that moved, moved because a
// column did.
fn ruler() -> layout.TableMeasure {
    var table: layout.TableMeasure = new layout.TableMeasure()
    for key: int in 1..20 {
        table.put(key, 100.0, 20.0)
    }
    return table
}

class Keys {
    pub next: int = 1
}

fn mirror(element: component.Element, keys: Keys) -> layout.LayoutNode {
    match element.arranger {
        none => {
            var leaf: layout.LayoutNode = layout.LayoutNode.leaf(element.tag, keys.next)
            keys.next = keys.next + 1
            leaf.spec = element.spec
            return leaf
        }
        some(arranger) => {
            var group: layout.LayoutNode = layout.LayoutNode.group(element.tag, arranger)
            group.spec = element.spec
            for index: int in 0..element.count() {
                group.add(mirror(element.child_at(index), keys))
            }
            return group
        }
    }
}

fn show(name: string, tree: component.Element, width: f64, height: f64) {
    io.println("== {name} ==")
    let root: layout.LayoutNode = mirror(tree, new Keys())
    var solver: layout.Solver = new layout.Solver(ruler())
    match solver.solve(root, geometry.Rect.of(0.0, 0.0, width, height)) {
        ok(done) => { io.print(layout.LayoutDump.tree(root)) }
        err(problem) => { io.println("  FAILED {problem.kind}: {problem.msg}") }
    }
}

/// A grid of `tiles` labels, configured by the words and numbers given.
fn shelf(words: List<string>, wordings: List<string>,
         numbers: List<string>, values: List<f64>,
         tiles: int) -> Result<component.Element> {
    var into: component.Builder = new component.Builder()
    into.open("Grid")
    for index: int in 0..words.len() {
        into.word(words[index], wordings[index])
    }
    for index: int in 0..numbers.len() {
        into.number(numbers[index], values[index])
    }
    for index: int in 0..tiles {
        into.open("Label")
        into.text("tile")
        into.close()
    }
    into.close()
    return into.finish()
}

fn fitted(tiles: int) -> Result<component.Element> {
    return shelf([], [], ["min_column", "column_gap", "row_gap"], [160.0, 10.0, 10.0], tiles)
}

/// The shelf `examples/gradients` puts its five gradients on: never under 160,
/// never over 260, and centred in whatever it does not use.
fn held(tiles: int) -> Result<component.Element> {
    return shelf(["justify"], ["center"],
                 ["min_column", "max_column", "column_gap", "row_gap"],
                 [160.0, 260.0, 10.0, 10.0], tiles)
}

/// The same pair as `shelf` writes, in the other order — source order is what
/// decides which of two refusals fires, so both orders are worth pinning.
fn numbers_first() -> Result<component.Element> {
    var into: component.Builder = new component.Builder()
    into.open("Grid")
    into.number("min_column", 160.0)
    into.word("columns", "1fr 1fr")
    into.close()
    return into.finish()
}

fn columns_on_a_run() -> Result<component.Element> {
    var into: component.Builder = new component.Builder()
    into.open("VStack")
    into.word("columns", "1fr 1fr")
    into.close()
    return into.finish()
}

fn gap_on_a_run() -> Result<component.Element> {
    var into: component.Builder = new component.Builder()
    into.open("HStack")
    into.number("column_gap", 10.0)
    into.close()
    return into.finish()
}

fn refuse(what: string, outcome: Result<component.Element>, clue: string) {
    match outcome {
        ok(tree) => { io.println("  {what} was allowed, and should not have been") }
        err(problem) => {
            io.println("  {what} is refused: {problem.kind == "bad_render"}")
            io.println("  and the message says why: {problem.msg.contains(clue)}")
        }
    }
}

fn drive() -> Result<bool> {
    io.println("-- a shelf that fits as many columns as it can --")
    // Eleven columns fit in 1968 and there are five tiles, so six tracks are
    // collapsed rather than left empty — auto-fit, not auto-fill.
    show("five tiles never leave a column empty beside them", fitted(5)?, 1968.0, 400.0)
    // 160 wide and a 10 gap is a 170 step: 5 fit in 900, 3 in 520, 1 in 300.
    show("five tiles in 900", fitted(5)?, 900.0, 400.0)
    show("the same five in 520", fitted(5)?, 520.0, 400.0)
    show("and in 300", fitted(5)?, 300.0, 400.0)

    io.println("-- a ceiling on a column, and the room it leaves --")
    // Without the ceiling every one of these would be a fifth of the window.
    // With it they stay tiles, and `justify` says where the row sits.
    show("five tiles, capped and centred, in 1368",
         held(5)?, 1368.0, 400.0)
    show("the same five in 1968",
         held(5)?, 1968.0, 400.0)
    show("and the short last row is centred on its own count",
         held(5)?, 668.0, 400.0)
    show("pushed to the end instead",
         shelf(["justify"], ["end"],
               ["min_column", "max_column", "column_gap"], [160.0, 260.0, 10.0], 5)?,
         1968.0, 400.0)
    show("spread between",
         shelf(["justify"], ["space_between"],
               ["min_column", "max_column", "column_gap"], [160.0, 260.0, 10.0], 5)?,
         1968.0, 400.0)

    io.println("-- columns written out --")
    show("160 points, a share, and the widest child",
         shelf(["columns"], ["160 1fr auto"], ["column_gap"], [10.0], 3)?,
         600.0, 200.0)
    show("two shares, unequal",
         shelf(["columns"], ["1fr 2fr"], ["column_gap"], [0.0], 2)?,
         600.0, 200.0)

    io.println("-- the same name twice is the last one, not both --")
    show("two shares, then three, is three",
         shelf(["columns", "columns"], ["1fr 1fr", "1fr 1fr 1fr"], ["column_gap"], [0.0], 3)?,
         600.0, 200.0)

    io.println("-- a ceiling is on the share, not on a number somebody wrote --")
    // 300 is written down and stays 300; the share beside it is what the
    // ceiling is for. Capping both would silently shrink an explicit column.
    show("a fixed column keeps its width under a ceiling of 100",
         shelf(["columns"], ["300 1fr"], ["max_column", "column_gap"], [100.0, 10.0], 2)?,
         600.0, 200.0)
    show("and auto keeps the widest child in it",
         shelf(["columns"], ["auto 1fr"], ["max_column", "column_gap"], [40.0, 10.0], 2)?,
         600.0, 200.0)

    io.println("-- a grid told nothing is the one column it always was --")
    show("two tiles, one column", shelf([], [], [], [], 2)?, 400.0, 200.0)

    io.println("-- what is refused --")
    refuse("columns and min_column together",
           shelf(["columns"], ["1fr 1fr"], ["min_column"], [160.0], 2),
           "decides the columns twice")
    refuse("min_column and columns, written the other way round",
           numbers_first(), "decides the columns twice")
    refuse("a column that is not a column",
           shelf(["columns"], ["160px 1fr"], [], [], 2),
           "a column is a number of points")
    refuse("a list with no columns in it",
           shelf(["columns"], ["   "], [], [], 2),
           "names no columns")
    refuse("a ceiling under the floor",
           shelf([], [], ["min_column", "max_column"], [200.0, 100.0], 2),
           "and no column could be both")
    refuse("a floor over the ceiling, the other way round",
           shelf([], [], ["max_column", "min_column"], [100.0, 200.0], 2),
           "and no column could be both")
    refuse("columns on a run", columns_on_a_run(), "write <Grid>")
    refuse("a column gap on a run", gap_on_a_run(), "write <Grid>")
    return ok(true)
}

fn main() {
    match drive() {
        ok(done) => {}
        err(problem) => { io.println("failed: {problem.msg}") }
    }
}
