// What a menu command means, so the platform can place it.
package surface

import cortado.host

/// The role a menu command plays.
///
/// This is the one idea that makes a menu portable, and it is worth the
/// paragraph. Every desktop platform has firm opinions about where certain
/// commands live, what they are called and what key they take: About and
/// Settings sit in the application menu on macOS and under Help and Edit on
/// Windows; Quit is Cmd-Q here and Alt-F4 there; and Cut, Copy and Paste must
/// be wired to the platform's own editing machinery — on macOS that means no
/// target at all, so the responder chain finds the focused field — or editing
/// stops working in every system control in your window.
///
/// So a command **with** a role is placed, named and keyed by the platform,
/// and the title and key you pass are advisory. A command with **no** role is
/// your own, and goes exactly where you put it.
///
/// Describing a menu as a tree of titles instead gives you a menu that is
/// right on the machine it was written on and wrong everywhere else.
pub enum CommandRole {
    /// An application command. Placed where you put it, named what you said.
    none
    about
    preferences
    quit
    hide
    undo
    redo
    cut
    copy
    paste
    select_all
    close
    minimize
    fullscreen

    pub fn code() -> int {
        return match self {
            none => host.CMD_NONE,
            about => host.CMD_ABOUT,
            preferences => host.CMD_PREFERENCES,
            quit => host.CMD_QUIT,
            hide => host.CMD_HIDE,
            undo => host.CMD_UNDO,
            redo => host.CMD_REDO,
            cut => host.CMD_CUT,
            copy => host.CMD_COPY,
            paste => host.CMD_PASTE,
            select_all => host.CMD_SELECT_ALL,
            close => host.CMD_CLOSE,
            minimize => host.CMD_MINIMIZE,
            fullscreen => host.CMD_FULLSCREEN,
        }
    }

    pub fn name() -> string {
        return match self {
            none => "none",
            about => "about",
            preferences => "preferences",
            quit => "quit",
            hide => "hide",
            undo => "undo",
            redo => "redo",
            cut => "cut",
            copy => "copy",
            paste => "paste",
            select_all => "select_all",
            close => "close",
            minimize => "minimize",
            fullscreen => "fullscreen",
        }
    }

    /// Whether the platform, rather than the application, handles this
    /// command. A handled role raises no `command` event: choosing Copy
    /// copies, and your program is not asked about it.
    pub fn is_platform_handled() -> bool {
        return match self {
            undo => true,
            redo => true,
            cut => true,
            copy => true,
            paste => true,
            select_all => true,
            close => true,
            minimize => true,
            fullscreen => true,
            hide => true,
            quit => true,
            none => false,
            about => false,
            preferences => false,
        }
    }

    /// The role this name spells, or nothing when no role does.
    ///
    /// The inverse of `name()`, beside it so the two lists are one list.
    /// `@command(role: "preferences")` is how a declaration names a role, and
    /// a table written anywhere else would drift from this one.
    pub static fn from_name(text: string) -> Option<CommandRole> {
        if text == "none" { return some(CommandRole.none)
        } else if text == "about" { return some(CommandRole.about)
        } else if text == "preferences" { return some(CommandRole.preferences)
        } else if text == "quit" { return some(CommandRole.quit)
        } else if text == "hide" { return some(CommandRole.hide)
        } else if text == "undo" { return some(CommandRole.undo)
        } else if text == "redo" { return some(CommandRole.redo)
        } else if text == "cut" { return some(CommandRole.cut)
        } else if text == "copy" { return some(CommandRole.copy)
        } else if text == "paste" { return some(CommandRole.paste)
        } else if text == "select_all" { return some(CommandRole.select_all)
        } else if text == "close" { return some(CommandRole.close)
        } else if text == "minimize" { return some(CommandRole.minimize)
        } else if text == "fullscreen" { return some(CommandRole.fullscreen)
        }
        return none
    }
}
