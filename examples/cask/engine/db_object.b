// One node of the database navigator's tree.
package engine

/// What a node in the navigator stands for.
///
/// Deliberately a small, database-agnostic set. A driver for a server-based
/// database has catalogs and schemas between the connection and the tables; a
/// file-based one like SQLite has neither, and its connection holds folders
/// directly. Both describe themselves with the same six words, so the
/// navigator never learns what a driver is.
///
/// `folder` is the one that does no work: it is "Tables", "Views", "Indexes"
/// — a grouping the driver invents so a connection with four hundred tables
/// does not open as four hundred rows. DBeaver calls these the same thing and
/// for the same reason.
pub enum(u8) ObjectKind {
    connection
    catalog
    schema
    folder
    table
    view
    index

    /// The glyph the navigator draws in front of the name.
    ///
    /// Letters rather than icons, because cortado's table cells are text and
    /// an image column is a control cortado does not have — the first thing a
    /// native outline view would bring. Named here rather than in the
    /// navigator so a driver that adds a kind adds its mark in one place, and
    /// kept clear of `▸`/`▾`, which the navigator draws itself for open and
    /// shut.
    pub fn mark() -> string {
        return match self {
            connection => "◈",
            catalog => "▣",
            schema => "▤",
            folder => "▪",
            table => "▦",
            view => "◫",
            index => "⋔",
        }
    }

    /// Whether a node of this kind is worth opening a data tab for.
    ///
    /// A folder has no rows; a table and a view do. An index does not either
    /// — selecting one shows the table it belongs to, which is what a person
    /// asking about an index wants to see.
    pub fn has_rows() -> bool {
        return match self {
            table => true,
            view => true,
            connection => false,
            catalog => false,
            schema => false,
            folder => false,
            index => false,
        }
    }

    pub fn name() -> string {
        return match self {
            connection => "connection",
            catalog => "catalog",
            schema => "schema",
            folder => "folder",
            table => "table",
            view => "view",
            index => "index",
        }
    }
}

/// One thing in the navigator: a connection, a folder, a table.
///
/// Children are **not** held here. A node knows its depth, its name and what
/// it is; asking a `Connection` for its children is how the tree grows, and
/// that is the difference between a navigator that opens instantly against a
/// thousand-table schema and one that reads the whole catalogue to draw a
/// row. DBeaver loads a node's children when the node is opened, and so does
/// this.
pub class DbObject {
    priv label: string = ""
    priv sort: ObjectKind = ObjectKind.folder
    priv owner: string = ""
    priv leafy: bool = false

    pub fn init(label: string, sort: ObjectKind, owner: string) {
        self.label = label
        self.sort = sort
        self.owner = owner
    }

    /// A node that has no children, so the navigator draws no twisty and
    /// never asks. A table *does* have children in DBeaver — its columns —
    /// and here it does not: columns are what the Columns tab is for, and a
    /// tree that opens into them is a tree a person has to close again.
    pub static fn leaf(label: string, sort: ObjectKind, owner: string) -> DbObject {
        var node: DbObject = new DbObject(label, sort, owner)
        node.leafy = true
        return node
    }

    pub fn name() -> string { return self.label }
    pub fn kind() -> ObjectKind { return self.sort }
    pub fn is_leaf() -> bool { return self.leafy }

    /// What this node hangs off: the table an index belongs to, the schema a
    /// table belongs to, or "" at the top. The driver decides what it means;
    /// the navigator only passes it back.
    pub fn parent_name() -> string { return self.owner }
}
