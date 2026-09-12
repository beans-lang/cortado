// What every database has to be able to answer.
package engine

/// One open database, whatever kind it is.
///
/// This is the seam the whole program is built around: nothing above it names
/// SQLite, and adding PostgreSQL means writing one class that implements this
/// and one that implements `Driver` — not touching the navigator, the editor,
/// the report or the window.
///
/// Every method answers a `Result`, including the ones that look like they
/// cannot fail. `label()` cannot fail for a file on disk and very much can for
/// a server that went away between one call and the next, and a signature
/// that is honest about the hard case is the one that does not have to change
/// when the second driver arrives.
///
/// **Nothing here may block for long.** These are called from the UI thread,
/// because that is where a person clicking a tree node is. A driver that
/// talks over a socket has to decide what it does about that, and the honest
/// options are a short timeout or a background fetch that calls back — not a
/// call that takes four seconds and freezes the window. SQLite reads a file
/// and returns, which is why this program can be written the simple way and
/// why the second driver will be the one that finds out what is missing.
pub interface Connection {
    /// What the status bar calls this connection.
    fn label() -> Result<string>

    /// The engine and its version, e.g. "SQLite 3.53.4".
    fn server() -> Result<string>

    /// The top of the navigator tree — for a file database one connection
    /// node, for a server one node per catalogue it can see.
    fn roots() -> Result<List<DbObject>>

    /// What opens under `node`. Called when a person opens it and not before.
    fn children_of(node: DbObject) -> Result<List<DbObject>>

    /// The rows of a table or a view, up to `limit`.
    fn rows_of(node: DbObject, limit: int) -> Result<Grid>

    /// One row per column: name, type, whether it may be null, its default,
    /// and whether it is part of the key. Five columns on every database
    /// worth supporting, which is why this is a `Grid` and not a list of some
    /// struct that would need a field the next driver does not have.
    fn columns_of(node: DbObject) -> Result<Grid>

    /// The `CREATE` statement, as close to what its author wrote as the
    /// database kept. "" when the database did not keep one.
    fn ddl_of(node: DbObject) -> Result<string>

    /// How many rows are really in a table, which the grid cannot say once it
    /// has stopped at a limit.
    fn count_of(node: DbObject) -> Result<int>

    /// Runs a statement a person typed and collects up to `limit` rows.
    fn run(sql: string, limit: int) -> Result<Grid>

    /// Whatever the database will say about itself — page size, encoding,
    /// character set, uptime. Free-form, because no two databases agree on
    /// what is worth saying, and the popover that shows it only prints lines.
    fn facts() -> Result<List<string>>

    /// Lets go of the file or the socket. Calling it twice is not an error:
    /// closing something already closed is what a window closing does.
    fn close() -> Result<bool>
}
