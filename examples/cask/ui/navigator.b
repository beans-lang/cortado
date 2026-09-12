// The database navigator: a tree, over the control that is one.
package ui

import cortado.widgets
import {Connection, DbObject, ObjectKind} from cask.engine

/// The tree down the left-hand side.
///
/// **Children are read when a node is opened and not before.** That is the
/// whole reason this is an `OutlineView` rather than a list: a schema with
/// four hundred tables costs one query when a person opens Tables, and
/// nothing at all until then. The control asks `child_count` and `child_at`
/// for the nodes it is drawing and no others.
///
/// A node is an `int`, and the mapping from one to a `DbObject` is the only
/// bookkeeping here. cortado never looks inside a node — it could have been a
/// pointer or a row id — so what it is is this class's choice: an index into
/// a list that only grows, which makes a node stable for as long as the
/// connection is open and makes `object_at` a lookup rather than a walk.
///
/// This file used to be a tree flattened into a one-column table by hand:
/// indentation by spaces, a twisty drawn as a character, and one click that
/// had to mean both "select" and "open" because there was no triangle to hit.
/// `cortado.widgets.OutlineView` is what replaced it, and the difference is
/// in this repository's history — the flattened version is what proved the
/// control was missing.
pub class Navigator implements widgets.OutlineNodes {
    priv link: Connection
    /// Every node this navigator has handed out, by node number minus one.
    /// Index 0 is node 1, because node 0 is the root and is never an object.
    priv known: List<DbObject> = []
    /// The children of each node, once asked for. A node the control has not
    /// opened is not in here at all.
    priv kids: Map<int, List<int>> = {}
    priv trouble: string = ""

    pub fn init(link: Connection) {
        self.link = link
    }

    // ---- nodes ----

    /// The node number for an object, making one if it is new.
    priv fn number_of(node: DbObject) -> int {
        self.known.push(node)
        return self.known.len()
    }

    pub fn object_at(node: int) -> Option<DbObject> {
        if node < 1 || node > self.known.len() { return none }
        return some(self.known[node - 1])
    }

    /// What went wrong the last time the control asked, or "".
    ///
    /// The source cannot refuse — it is called while the platform is drawing,
    /// and there is nothing the platform could do with a `Result` — so a
    /// failed query answers "no children" and leaves the reason here for the
    /// window to show.
    pub fn trouble_says() -> string {
        return self.trouble
    }

    /// Forgets every node, so the next question re-reads the database.
    ///
    /// Node numbers are *not* reused: a fresh set is handed out, and the
    /// control is told to reload, which makes it ask again from the root. The
    /// alternative — keeping the numbers and changing what they mean — is how
    /// a selection ends up pointing at a different table than the one a
    /// person clicked.
    pub fn forget() {
        self.known = []
        self.kids = {}
        self.trouble = ""
    }

    // ---- what the control asks ----

    /// The children of `node`, read once and remembered.
    ///
    /// Remembered because the control asks for the count and then for each
    /// child, and asking the database once per question would mean a query
    /// per row drawn. This is the cache that makes `child_at` free.
    priv fn children_of(node: int) -> List<int> {
        match self.kids.get(node) {
            some(kept) => {
                var copy: List<int> = []
                for one: int in kept { copy.push(one) }
                return move copy
            }
            none => {}
        }

        // Numbered as they are read rather than collected first: a `match`
        // arm borrows what it binds, so a driver's own list is not this
        // function's to take.
        var numbers: List<int> = []
        if node == 0 {
            match self.link.roots() {
                ok(tops) => {
                    for child: DbObject in tops { numbers.push(self.number_of(child)) }
                }
                err(problem) => { self.trouble = "{problem.kind}: {problem.msg}" }
            }
        } else {
            match self.object_at(node) {
                none => {}
                some(owner) => {
                    match self.link.children_of(owner) {
                        ok(under) => {
                            for child: DbObject in under {
                                numbers.push(self.number_of(child))
                            }
                        }
                        err(problem) => { self.trouble = "{problem.kind}: {problem.msg}" }
                    }
                }
            }
        }
        var copy: List<int> = []
        for one: int in numbers { copy.push(one) }
        self.kids.set(node, move numbers)
        return move copy
    }

    pub fn child_count(node: int) -> int {
        return self.children_of(node).len()
    }

    pub fn child_at(node: int, index: int) -> int {
        let mine: List<int> = self.children_of(node)
        if index < 0 || index >= mine.len() { return 0 }
        return mine[index]
    }

    /// Whether a node can be opened at all.
    ///
    /// Answered from the object's own kind rather than by counting its
    /// children, and that is the difference the header insists on: a folder
    /// nobody has read yet has no children to report and must still draw a
    /// twisty, or a person can never open it to find out.
    pub fn expandable(node: int) -> bool {
        if node == 0 { return true }
        match self.object_at(node) {
            none => { return false }
            some(thing) => { return !thing.is_leaf() }
        }
    }

    pub fn cell(node: int, column: int) -> string {
        match self.object_at(node) {
            none => { return "" }
            some(thing) => {
                if column == 0 { return "{thing.kind().mark()} {thing.name()}" }
                return thing.kind().name()
            }
        }
    }
}
