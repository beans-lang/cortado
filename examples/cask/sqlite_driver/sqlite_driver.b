// The SQLite driver.
package sqlite_driver

import github.com/beans-lang/sqlite
import {Connection, Driver} from cask.engine

/// Opens SQLite files, and an in-memory one when asked for nothing.
///
/// The whole of what a second database needs to provide, in thirty lines:
/// a name, a hint, a guess at whether a target is its, and a way in. Nothing
/// in the window knows this class exists — `main.b` names it once, puts it in
/// the registry, and everything after that goes through `engine.Driver`.
pub class SqliteDriver implements Driver {
    pub fn init() {}

    pub fn name() -> string { return "SQLite" }

    pub fn target_hint() -> string {
        return "a path to a .db file, or nothing for a sample database in memory"
    }

    /// By the shape of the name, never by opening it. A driver that opened a
    /// file to decide whether it could open the file would make choosing a
    /// driver as slow as connecting, and on a server driver it would mean a
    /// socket per guess.
    pub fn handles(target: string) -> bool {
        if target == "" { return true }
        if target.contains("://") { return false }
        return target.ends_with(".db") || target.ends_with(".sqlite") ||
               target.ends_with(".sqlite3") || target.ends_with(".db3")
    }

    pub fn connect(target: string) -> Result<Connection> {
        if target == "" {
            let memory: sqlite.Database = sqlite.Database.open_memory()?
            seed(memory)?
            return ok(new SqliteConnection(memory, "a sample database, in memory"))
        }
        // Read-only, because this is a browser. Opening read-write would
        // create an empty database out of a typo, which is a bad answer to
        // "show me this file".
        let file: sqlite.Database = sqlite.Database.open_read_only(target)?
        return ok(new SqliteConnection(file, target))
    }
}
