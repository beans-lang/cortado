// A database to browse when nobody named one.
package sqlite_driver

import github.com/beans-lang/sqlite

/// Builds a small, real schema in memory.
///
/// The point of seeding rather than shipping a `.db` file is that a binary
/// with no data beside it still opens something worth looking at — and the
/// schema below is chosen to exercise the browser rather than to be pretty:
/// a foreign key, a UNIQUE index, a NOT NULL with a default, a NULL in a
/// column that allows one, a view, and a date column, because a grid that has
/// never been shown a NULL is a grid nobody has tested.
///
/// The SQL is one raw string. Beans has no `+` for strings, and a raw string
/// spans lines and opens no interpolation — which SQL needs, because a
/// `LIKE 'x%'` pattern and a `{` in a trigger body both mean something else
/// inside an ordinary string. A raw string ends at the first `"`, so every
/// literal below is single-quoted, which is the SQL standard's own spelling.
pub fn seed(db: sqlite.Database) -> Result<bool> {
    db.exec(r"
CREATE TABLE roasters(
  id       INTEGER PRIMARY KEY,
  name     TEXT NOT NULL,
  city     TEXT,
  founded  INTEGER
);
CREATE TABLE beans(
  id         INTEGER PRIMARY KEY,
  roaster    INTEGER NOT NULL REFERENCES roasters(id),
  name       TEXT NOT NULL,
  origin     TEXT NOT NULL,
  process    TEXT NOT NULL DEFAULT 'washed',
  score      REAL,
  roasted_on TEXT NOT NULL
);
CREATE UNIQUE INDEX beans_by_name ON beans(roaster, name);
CREATE INDEX beans_by_day ON beans(roasted_on);
CREATE VIEW recent AS
  SELECT b.name, b.origin, b.roasted_on, r.name AS roaster
    FROM beans b JOIN roasters r ON r.id = b.roaster
   ORDER BY b.roasted_on DESC;
")?

    let tx: sqlite.Transaction = db.begin()?
    put_roaster(db, 1, "Clever Dripper", some("Lisbon"), 2011)?
    put_roaster(db, 2, "Ninth Street", some("Melbourne"), 1998)?
    put_roaster(db, 3, "Slow Pour", some("Kyoto"), 2016)?
    // A city nobody filled in. The grid has to show this as NULL and not as
    // an empty cell, which is a difference a person reading a schema cares
    // about and a naive browser loses.
    put_roaster(db, 4, "Backyard", none, 2021)?

    put_bean(db, 1, "Yirgacheffe Kochere", "Ethiopia", "washed", some(89.5), "2026-08-14")?
    put_bean(db, 1, "Huila Reserve", "Colombia", "honey", some(87.0), "2026-08-22")?
    put_bean(db, 2, "Gesha Hartmann", "Panama", "natural", some(92.25), "2026-09-01")?
    put_bean(db, 2, "Antigua Pastoral", "Guatemala", "washed", some(85.75), "2026-07-30")?
    put_bean(db, 3, "Kirinyaga AA", "Kenya", "washed", some(90.0), "2026-09-05")?
    put_bean(db, 3, "Sidama Bensa", "Ethiopia", "natural", some(88.25), "2026-09-09")?
    put_bean(db, 4, "House Blend", "Blend", "washed", some(79.0), "2026-09-11")?
    // A score nobody has given yet, so a REAL column has a NULL in it too.
    put_bean(db, 4, "Tuesday Lot", "Brazil", "natural", none, "2026-09-12")?
    tx.commit()?
    return ok(true)
}

/// One roaster. `city` is an `Option` rather than a string with a sentinel,
/// because SQL NULL and the empty string are different values and a seed that
/// blurred them would hide the bug it is here to expose.
fn put_roaster(db: sqlite.Database, id: int, name: string, city: Option<string>,
    founded: int) -> Result<bool> {
    let row: sqlite.Statement = db.prepare(
        "INSERT INTO roasters(id, name, city, founded) VALUES (?1, ?2, ?3, ?4)")?
    row.bind_int(1, id)?
    row.bind_text(2, name)?
    match city {
        some(where) => { row.bind_text(3, where)? }
        none => { row.bind_null(3)? }
    }
    row.bind_int(4, founded)?
    row.step()?
    row.finalize()?
    return ok(true)
}

fn put_bean(db: sqlite.Database, roaster: int, name: string, origin: string,
    process: string, score: Option<f64>, day: string) -> Result<bool> {
    let row: sqlite.Statement = db.prepare(
        r"INSERT INTO beans(roaster, name, origin, process, score, roasted_on)
          VALUES (?1, ?2, ?3, ?4, ?5, ?6)")?
    row.bind_int(1, roaster)?
    row.bind_text(2, name)?
    row.bind_text(3, origin)?
    row.bind_text(4, process)?
    match score {
        some(cupped) => { row.bind_float(5, cupped)? }
        none => { row.bind_null(5)? }
    }
    row.bind_text(6, day)?
    row.step()?
    row.finalize()?
    return ok(true)
}
