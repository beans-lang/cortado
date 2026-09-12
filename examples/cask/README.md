# cask — a database browser

```
beansc build examples/cask/main.b -o build/cask && ./build/cask
./build/cask some.db          # or point it at a file
./build/cask --dump           # what the gate runs: no window, prints what it read
```

A SQLite browser with DBeaver's shape: a navigator tree down the left, an
editor with tabs on the right, the SQL editor split so a statement sits above
its results, and a status bar that says what you are connected to.

It exists to be **used** rather than read. Every other example here shows one
control; this one is an application, and an application is the only thing that
finds out what a control set is missing.

## Adding another database

Nothing above `cask.engine` knows SQLite exists.

| you write | it implements |
|---|---|
| `PostgresDriver` | `engine.Driver` — a name, a hint, `handles`, `connect` |
| `PostgresConnection` | `engine.Connection` — eleven methods, all `Result` |


and one line in `main.b`:

```beans
drivers.add(new PostgresDriver())
```

The navigator, the editor, the report and the window do not change. `roots()`
and `children_of()` are what let a server driver put catalogues and schemas
between the connection and the tables while a file database has neither —
the navigator only ever asks what opens under a node, and asks it when a
person opens one.

**The one thing a second driver will find**: every `Connection` method is
called from the UI thread, because that is where a person clicking a tree node
is. SQLite reads a file and returns. A driver talking over a socket has to
decide what it does about that, and the honest answers are a short timeout or
a background fetch that calls back — not a call that takes four seconds and
freezes the window.

## What this found in cortado

Four bugs, each invisible until a real program ran into it. Every one is fixed,
and every fix has a test that fails when the fix is reverted.

| what | where | how it showed |
|---|---|---|
| every toolbar item carried the **first** command's words and token | `src/mac/shell.m` — a 4-character prefix parsed as 5 | four buttons, all labelled Reload |
| a **tab page** was given a frame AppKit owns | `src/mac/view.m` | every page drawn 46 points too high, on top of the tab strip |
| a **split view** reported cortado's own layout as a value the user changed | `src/mac/pane.m`, `property.m` | a sidebar asked for at 210 points came up at half the window |
| a **table** reported the program's own `select` as a click | `src/mac/table.m`, and the same on GTK4 and Win32 | the navigator opened the root node, selected it, and heard the selection as a click that shut it again |

Three of those are one rule, which cortado's header already states and which
the GTK4 host has followed since it was written: **`ctd_set_*` changes a
control silently.** A program that hears its own writes feeds itself. The
macOS host broke it in three places and the Win32 host in one, and all four
now carry the same counter under the same name.

Three things were missing rather than wrong:

- **there were no system icons.** A toolbar of words is not what a database
  browser looks like on any platform. cortado now names twenty-seven icon
  *roles* and each host draws its own — SF Symbols on macOS and iOS, the
  freedesktop theme on GTK, the standard toolbar bitmap and shell stock icons
  on Windows — and says which roles it has, so cask's toolbar is icons where
  there are icons and words where there are not.


- **`LayoutSpec` could not say "this tall, any width".** The obvious spelling,
  `fixed(0.0, 96.0)`, pins the width to zero — laid out exactly as written,
  reporting nothing, invisible. `examples/panes.b` had already shipped that
  way. There is now `LayoutSpec.tall` and `LayoutSpec.wide`.
- **`ctd_toolbar_count` could say how many items a toolbar had and not which.**
  That is why the toolbar bug survived a green suite. There is now
  `ctd_toolbar_label`, and `tests/shell.b` asserts each item carries its own
  command's words in the menu's order.

## The control this example asked for

**cortado had no outline view.** Thirty widget kinds and none was a tree, so
the first version of `ui/navigator.b` was a tree flattened by hand: a
one-column table whose cells carried their own indent and their own twisty as
characters, and one click that had to mean both "select" and "open" because
there was no triangle to hit. It worked, and it was not the same thing — no
keyboard tree navigation, indentation by spaces in a proportional font, and
every node's children read whether or not anyone opened them.

`cortado.widgets.OutlineView` is what replaced it: `NSOutlineView`, a
`GtkColumnView` over a `GtkTreeListModel`, a `SysTreeView32`. The navigator is
now a data source with four methods and no drawing of its own, and the
difference that matters is the one the flattened version could not have: a
node's children are read **when it is opened and not before**, so a schema
with four hundred tables costs one query when a person opens Tables.

UIKit has none, and says so rather than substituting an indented list — what a
phone has is a collection-view layout, not a control. `tests/outline.b` opens
one node of a 400,004-node tree and asserts it cost under a thousand questions.

Smaller things a second driver or a longer session would want:

- **no way to open a file**: cask takes a path on the command line. cortado has
  file dialogs; a connection dialog is a screen nobody has written yet.
- **the filter searches the page, not the table.** `Grid.filtered` runs over
  the at most 500 rows that were read. Searching the whole table is a `WHERE`
  clause, which is what the SQL tab is for.
- **read-only.** Opening a file uses `open_read_only`, because a browser that
  creates an empty database out of a typo is a bad answer to "show me this
  file". Editing cells is a different program.
