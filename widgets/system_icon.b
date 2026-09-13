// The system's own icons, named by what they are for.
package widgets

import cortado.host

/// One of the system's icons, named by role.
///
/// Every platform ships an icon set and no two agree on what anything is
/// called: macOS and iOS have SF Symbols (`arrow.clockwise`), GTK has the
/// freedesktop theme (`view-refresh-symbolic`), Windows has the standard
/// toolbar bitmap and the shell's stock icons (`STD_FILEOPEN`, `SIID_FOLDER`).
/// Naming one of those in a program is writing a program for one platform.
///
/// So this names the **job**, and each host draws its own picture for it. That
/// is the whole reason to use the system's set rather than ship pictures: a
/// person already knows their own system's icon for "refresh", and a drawing
/// this library invented would be one more thing for them to learn.
///
/// **Not every role exists everywhere.** Windows' standard toolbar bitmap has
/// fifteen images and no "run" or "database" among them. `available()` is the
/// question to ask, and a program that shows a word where the answer is no
/// looks better than one showing an empty square — see `examples/cask`, whose
/// toolbar does exactly that.
pub enum(u8) SystemIcon {
    none
    refresh
    add
    remove
    delete
    open
    save
    search
    run
    stop
    back
    forward
    cut
    copy
    paste
    undo
    redo
    print
    settings
    info
    warning
    error
    help
    document
    folder
    database
    table

    /// The number the header gives this role.
    ///
    /// Spelled out rather than cast, because an `enum(u8)` does not convert to
    /// an integer and should not: the ABI's numbering is the header's, and a
    /// cast would make reordering this list an ABI change nobody noticed.
    pub fn code() -> int {
        return match self {
            none => host.ICON_NONE,
            refresh => host.ICON_REFRESH,
            add => host.ICON_ADD,
            remove => host.ICON_REMOVE,
            delete => host.ICON_DELETE,
            open => host.ICON_OPEN,
            save => host.ICON_SAVE,
            search => host.ICON_SEARCH,
            run => host.ICON_RUN,
            stop => host.ICON_STOP,
            back => host.ICON_BACK,
            forward => host.ICON_FORWARD,
            cut => host.ICON_CUT,
            copy => host.ICON_COPY,
            paste => host.ICON_PASTE,
            undo => host.ICON_UNDO,
            redo => host.ICON_REDO,
            print => host.ICON_PRINT,
            settings => host.ICON_SETTINGS,
            info => host.ICON_INFO,
            warning => host.ICON_WARNING,
            error => host.ICON_ERROR,
            help => host.ICON_HELP,
            document => host.ICON_DOCUMENT,
            folder => host.ICON_FOLDER,
            database => host.ICON_DATABASE,
            table => host.ICON_TABLE,
        }
    }

    /// The role a number stands for, or `none` for one this build does not
    /// have. Used to read `P_ICON` back.
    pub static fn of(code: int) -> SystemIcon {
        for icon: SystemIcon in SystemIcon.all() {
            if icon.code() == code { return icon }
        }
        return SystemIcon.none
    }

    /// Every role, in the header's order.
    pub static fn all() -> List<SystemIcon> {
        return [SystemIcon.none, SystemIcon.refresh, SystemIcon.add,
                SystemIcon.remove, SystemIcon.delete, SystemIcon.open,
                SystemIcon.save, SystemIcon.search, SystemIcon.run,
                SystemIcon.stop, SystemIcon.back, SystemIcon.forward,
                SystemIcon.cut, SystemIcon.copy, SystemIcon.paste,
                SystemIcon.undo, SystemIcon.redo, SystemIcon.print,
                SystemIcon.settings, SystemIcon.info, SystemIcon.warning,
                SystemIcon.error, SystemIcon.help, SystemIcon.document,
                SystemIcon.folder, SystemIcon.database, SystemIcon.table]
    }

    /// What this platform calls it: `arrow.clockwise` on macOS,
    /// `view-refresh-symbolic` on GTK, `STD_FILEOPEN` on Windows.
    ///
    /// **This is for reading, not for passing back in.** It exists so a
    /// misdrawn toolbar can be diagnosed without a screenshot, and so a suite
    /// can check that a host's mapping has no holes and no duplicates.
    /// Nothing portable should compare these strings.
    ///
    /// Refused with `out_of_range` where this platform has no icon for the
    /// role, which is also how `available` answers.
    pub fn platform_name() -> Result<string> {
        let code: int = self.code()
        unsafe {
            return host.HostText.read("name the {self.name()} icon",
                fn(out: RawPtr<i8>, cap: i32) -> i32 {
                    return host.ctd_icon_name(code as i32, out, cap)
                })
        }
    }

    /// Whether this platform can draw it. `none` is always available: it is
    /// the absence of an icon, which every platform has.
    pub fn available() -> bool {
        match self.platform_name() {
            ok(named) => { return true }
            err(problem) => { return false }
        }
    }

    pub fn name() -> string {
        return match self {
            none => "none",
            refresh => "refresh",
            add => "add",
            remove => "remove",
            delete => "delete",
            open => "open",
            save => "save",
            search => "search",
            run => "run",
            stop => "stop",
            back => "back",
            forward => "forward",
            cut => "cut",
            copy => "copy",
            paste => "paste",
            undo => "undo",
            redo => "redo",
            print => "print",
            settings => "settings",
            info => "info",
            warning => "warning",
            error => "error",
            help => "help",
            document => "document",
            folder => "folder",
            database => "database",
            table => "table",
        }
    }

    /// The role this name spells, or nothing when no role does.
    ///
    /// The inverse of `name()`, and it lives beside it so the two lists are
    /// one list. A caller with its own string-to-role table would have a
    /// second one to keep in step, and the way that fails is a role quietly
    /// becoming `none` — an empty square where an icon was asked for.
    pub static fn from_name(text: string) -> Option<SystemIcon> {
        if text == "none" { return some(SystemIcon.none)
        } else if text == "refresh" { return some(SystemIcon.refresh)
        } else if text == "add" { return some(SystemIcon.add)
        } else if text == "remove" { return some(SystemIcon.remove)
        } else if text == "delete" { return some(SystemIcon.delete)
        } else if text == "open" { return some(SystemIcon.open)
        } else if text == "save" { return some(SystemIcon.save)
        } else if text == "search" { return some(SystemIcon.search)
        } else if text == "run" { return some(SystemIcon.run)
        } else if text == "stop" { return some(SystemIcon.stop)
        } else if text == "back" { return some(SystemIcon.back)
        } else if text == "forward" { return some(SystemIcon.forward)
        } else if text == "cut" { return some(SystemIcon.cut)
        } else if text == "copy" { return some(SystemIcon.copy)
        } else if text == "paste" { return some(SystemIcon.paste)
        } else if text == "undo" { return some(SystemIcon.undo)
        } else if text == "redo" { return some(SystemIcon.redo)
        } else if text == "print" { return some(SystemIcon.print)
        } else if text == "settings" { return some(SystemIcon.settings)
        } else if text == "info" { return some(SystemIcon.info)
        } else if text == "warning" { return some(SystemIcon.warning)
        } else if text == "error" { return some(SystemIcon.error)
        } else if text == "help" { return some(SystemIcon.help)
        } else if text == "document" { return some(SystemIcon.document)
        } else if text == "folder" { return some(SystemIcon.folder)
        } else if text == "database" { return some(SystemIcon.database)
        } else if text == "table" { return some(SystemIcon.table)
        }
        return none
    }
}
