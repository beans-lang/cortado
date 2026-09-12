// SQLite, answering the questions every database is asked.
package sqlite_driver

import sqlite
import {Connection, DbObject, Grid, ObjectKind} from cask.engine

/// How many rows one screenful of browsing reads before it stops.
///
/// A browser is not a report writer. Reading a hundred million rows into a
/// grid to show the first forty is the mistake this constant exists to not
/// make, and the window says when it has been hit rather than letting the
/// table look like it ends here.
pub const PAGE: int = 500

/// One open SQLite file, behind the database-agnostic interface.
///
/// Everything the navigator asks for goes through one function, `run`,
/// because in SQLite the schema *is* queryable — `sqlite_master` is a table
/// and `PRAGMA table_info` returns rows. So "list the tables" and "show me
/// this table" are the same operation with different SQL, and there is one
/// piece of code that steps a statement and turns cells into text.
pub class SqliteConnection implements Connection {
    priv db: sqlite.Database
    priv where: string = ""
    priv live: bool = true

    pub fn init(db: sqlite.Database, where: string) {
        self.db = db
        self.where = where
    }

    // ---- what the program is looking at ----

    pub fn label() -> Result<string> {
        return ok(self.where)
    }

    pub fn server() -> Result<string> {
        return ok("SQLite {sqlite.version()}")
    }

    // ---- the tree ----

    /// SQLite has no catalogues and no schemas, so the connection holds the
    /// three folders directly. A server driver would answer one node per
    /// database here and put the folders two levels down; the navigator does
    /// not care which, because it only ever asks what opens under a node.
    pub fn roots() -> Result<List<DbObject>> {
        return ok([new DbObject(self.where, ObjectKind.connection, "")])
    }

    pub fn children_of(node: DbObject) -> Result<List<DbObject>> {
        match node.kind() {
            connection => {
                return ok([
                    new DbObject("Tables", ObjectKind.folder, "table"),
                    new DbObject("Views", ObjectKind.folder, "view"),
                    new DbObject("Indexes", ObjectKind.folder, "index"),
                ])
            }
            folder => { return self.folder_children(node) }
            table => { return ok([]) }
            view => { return ok([]) }
            index => { return ok([]) }
            catalog => { return ok([]) }
            schema => { return ok([]) }
        }
    }

    /// The objects of one `sqlite_master` type. A folder carries the type it
    /// stands for in `parent_name`, which is why this needs no table of
    /// folder names to match against.
    priv fn folder_children(node: DbObject) -> Result<List<DbObject>> {
        let sort: string = node.parent_name()
        var kind: ObjectKind = ObjectKind.table
        if sort == "view" { kind = ObjectKind.view }
        if sort == "index" { kind = ObjectKind.index }

        // `sqlite_%` is excluded because those are SQLite's own bookkeeping —
        // `sqlite_sequence`, `sqlite_stat1` — and a browser that lists them
        // invites someone to edit one.
        let rows: sqlite.Statement = self.db.prepare(
            r"SELECT name, COALESCE(tbl_name, '') FROM sqlite_master
               WHERE type = ?1 AND name NOT LIKE 'sqlite_%'
               ORDER BY name")?
        rows.bind_text(1, sort)?
        var out: List<DbObject> = []
        for rows.step()? {
            out.push(DbObject.leaf(rows.column_text(0), kind, rows.column_text(1)))
        }
        rows.finalize()?
        return ok(move out)
    }

    // ---- what is in one object ----

    pub fn rows_of(node: DbObject, limit: int) -> Result<Grid> {
        if !node.kind().has_rows() {
            return err("a {node.kind().name()} has no rows of its own",
                "not_a_relation")
        }
        return self.run("SELECT * FROM {quoted(node.name())}", limit)
    }

    pub fn columns_of(node: DbObject) -> Result<Grid> {
        var subject: string = node.name()
        // An index's columns are the columns of the table it indexes, which
        // is what a person clicking an index is asking about.
        if node.kind() == ObjectKind.index { subject = node.parent_name() }
        if subject == "" { return ok(Grid.empty()) }
        return self.run("PRAGMA table_info({quoted(subject)})", PAGE)
    }

    pub fn ddl_of(node: DbObject) -> Result<string> {
        let rows: sqlite.Statement = self.db.prepare(
            "SELECT sql FROM sqlite_master WHERE name = ?1")?
        rows.bind_text(1, node.name())?
        var text: string = ""
        if rows.step()? {
            match rows.column_text_opt(0) {
                some(sql) => { text = sql }
                none => { text = "" }
            }
        }
        rows.finalize()?
        return ok(text)
    }

    pub fn count_of(node: DbObject) -> Result<int> {
        if !node.kind().has_rows() { return ok(0) }
        let rows: sqlite.Statement = self.db.prepare(
            "SELECT count(*) FROM {quoted(node.name())}")?
        var total: int = 0
        if rows.step()? { total = rows.column_int(0) }
        rows.finalize()?
        return ok(total)
    }

    // ---- the one reader ----

    /// Runs `sql` and collects up to `limit` rows.
    ///
    /// Every value comes back as text, including the integers, because a
    /// table control shows text and the alternative is a second conversion at
    /// the moment of drawing. NULL is the one value that must not become `""`
    /// — a NULL and an empty string look identical in a grid and are not the
    /// same thing — so it is shown as the word SQL itself uses.
    pub fn run(sql: string, limit: int) -> Result<Grid> {
        let statement: sqlite.Statement = self.db.prepare(sql)?
        let wide: int = statement.column_count()
        if wide == 0 {
            // A statement with no result columns: CREATE, INSERT, a PRAGMA
            // that sets rather than asks. It still has to be stepped, or it
            // never runs.
            statement.step()?
            statement.finalize()?
            return ok(Grid.empty())
        }

        var titles: List<string> = []
        var column: int = 0
        for column < wide {
            titles.push(statement.column_name(column))
            column = column + 1
        }

        var grid: Grid = new Grid(titles)
        var seen: int = 0
        var more: bool = false
        for statement.step()? {
            if seen >= limit {
                more = true
                break
            }
            var row: List<string> = []
            column = 0
            for column < wide {
                match statement.column_text_opt(column) {
                    some(text) => { row.push(text) }
                    none => { row.push("NULL") }
                }
                column = column + 1
            }
            grid.push_row(move row)?
            seen = seen + 1
        }
        grid.set_complete(!more)
        statement.finalize()?
        return ok(grid)
    }

    pub fn facts() -> Result<List<string>> {
        var lines: List<string> = [self.server()?, self.where]
        for question: string in ["page_size", "encoding", "journal_mode", "page_count"] {
            match self.run("PRAGMA {question}", 1) {
                ok(found) => {
                    if found.row_count() > 0 {
                        lines.push("{question}: {found.cell(0, 0)}")
                    }
                }
                err(problem) => {}
            }
        }
        return ok(move lines)
    }

    pub fn close() -> Result<bool> {
        if !self.live { return ok(true) }
        self.live = false
        return self.db.close()
    }
}

/// A name, quoted so SQLite reads it as an identifier.
///
/// This is not decoration. A table may legally be called `order` or `select`
/// or `my table`, and `SELECT * FROM order` is a syntax error. Doubling any
/// embedded quote is what closes the hole a name like `x"; DROP TABLE y; --`
/// would otherwise open — and these names come out of `sqlite_master`, which
/// means they come from whoever wrote the file this program was pointed at.
pub fn quoted(name: string) -> string {
    let doubled: string = name.replace("\"", "\"\"")
    return "\"{doubled}\""
}
