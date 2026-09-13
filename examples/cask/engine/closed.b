// A connection to nothing.
package engine

/// A `Connection` with no database behind it, which refuses everything.
///
/// **The null object exists for one reason: a screen is built before a
/// database is opened.** `site/browser.bx` declares its session with
/// `@inject`, and an injected field needs a value to start from — an interface
/// has none, and a screen that could not be constructed until a file had been
/// opened would be a screen no test could build and no application could show
/// while it waited.
///
/// Every method refuses with the same word. That is deliberate: a caller that
/// handles `Result` at all already handles this, and a program that showed
/// empty tables instead would be a program where "nothing is open" and "this
/// table has no rows" look the same.
pub class ClosedConnection implements Connection {
    pub fn init() {}

    pub fn label() -> Result<string> {
        return err("no database is open", "not_open")
    }

    pub fn server() -> Result<string> {
        return err("no database is open", "not_open")
    }

    pub fn roots() -> Result<List<DbObject>> {
        return err("no database is open", "not_open")
    }

    pub fn children_of(node: DbObject) -> Result<List<DbObject>> {
        return err("no database is open", "not_open")
    }

    pub fn rows_of(node: DbObject, limit: int) -> Result<Grid> {
        return err("no database is open", "not_open")
    }

    pub fn columns_of(node: DbObject) -> Result<Grid> {
        return err("no database is open", "not_open")
    }

    pub fn ddl_of(node: DbObject) -> Result<string> {
        return err("no database is open", "not_open")
    }

    pub fn count_of(node: DbObject) -> Result<int> {
        return err("no database is open", "not_open")
    }

    pub fn run(sql: string, limit: int) -> Result<Grid> {
        return err("no database is open", "not_open")
    }

    pub fn facts() -> Result<List<string>> {
        return err("no database is open", "not_open")
    }

    /// The one that does not refuse. Closing something already closed is what
    /// a window closing does, and the interface says so.
    pub fn close() -> Result<bool> {
        return ok(true)
    }
}
