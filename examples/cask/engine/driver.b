// How a kind of database is opened.
package engine

/// One database engine cask knows how to talk to.
///
/// A driver is a *factory with a name*, which is all the navigator needs to
/// offer a list of what can be connected to. DBeaver's driver manager is this
/// plus a download step for a JDBC jar; cask's drivers are compiled in, so
/// there is nothing to download and nothing to configure.
pub interface Driver {
    /// What the connection dialog calls it: "SQLite", "PostgreSQL".
    fn name() -> string

    /// What `target` means for this driver, in one line, so the program can
    /// say "a path to a .db file" rather than leaving a person guessing.
    fn target_hint() -> string

    /// Whether this driver can open `target` — usually by its shape, never by
    /// opening it. The navigator asks every driver this before it asks one to
    /// connect, and a driver that opened a socket to answer would make
    /// choosing a driver as slow as connecting.
    fn handles(target: string) -> bool

    /// Opens it. An empty `target` means "whatever you offer with nothing" —
    /// for SQLite an in-memory database, for a server an error saying what it
    /// needed.
    fn connect(target: string) -> Result<Connection>
}
