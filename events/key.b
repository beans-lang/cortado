// Which key, when the news is the key and not what it typed.
package events

import cortado.host

/// A key that types nothing, or the fact that this one typed something.
///
/// **There is no member here for a letter, a digit or a punctuation mark, and
/// that is the design rather than an omission.** A name per character is a
/// keyboard layout written into a library: the key to the left of `1` is a
/// different character on a US, a German and a French keyboard, and the key
/// that types `z` on one types `y` on another. What a program wants to know
/// about those keys is what was *typed* — which arrives as the event's `text`,
/// already composed, already through the input method, correct for a dead-key
/// accent and for a Japanese keyboard. So every such key is `character` and
/// the news is in the text.
///
/// What is named is the keys that type nothing and mean the same thing on
/// every keyboard there is. A program listening for Escape, or for the arrow
/// that moves a selection, is asking about the key and not about a character,
/// and those are the same keys everywhere.
///
/// `space` is in both halves, which is not a contradiction: a program watching
/// for the space bar on a button wants the key, and one filling a text field
/// wants the character. Both are true of the same keystroke and both are
/// reported.
pub enum(u8) Key {
    /// A key this platform has and cortado does not name.
    unknown
    /// It typed something, and the event's `text` is what.
    character
    escape
    tab
    ret
    space
    backspace
    delete
    left
    right
    up
    down
    home
    end
    page_up
    page_down
    f1
    f2
    f3
    f4
    f5
    f6
    f7
    f8
    f9
    f10
    f11
    f12

    /// The number the header gives this key. Beans has no implicit conversion
    /// between an `enum(u8)` and an integer, and an `enum(u8)` is not a C ABI
    /// type either, so the crossing is written out — the same shape
    /// `WidgetKind` and `SystemIcon` use, and held to the header by
    /// `tools/check_constants.sh`.
    pub fn code() -> int {
        return match self {
            unknown => host.KEY_UNKNOWN,
            character => host.KEY_CHARACTER,
            escape => host.KEY_ESCAPE,
            tab => host.KEY_TAB,
            ret => host.KEY_RETURN,
            space => host.KEY_SPACE,
            backspace => host.KEY_BACKSPACE,
            delete => host.KEY_DELETE,
            left => host.KEY_LEFT,
            right => host.KEY_RIGHT,
            up => host.KEY_UP,
            down => host.KEY_DOWN,
            home => host.KEY_HOME,
            end => host.KEY_END,
            page_up => host.KEY_PAGE_UP,
            page_down => host.KEY_PAGE_DOWN,
            f1 => host.KEY_F1,
            f2 => host.KEY_F2,
            f3 => host.KEY_F3,
            f4 => host.KEY_F4,
            f5 => host.KEY_F5,
            f6 => host.KEY_F6,
            f7 => host.KEY_F7,
            f8 => host.KEY_F8,
            f9 => host.KEY_F9,
            f10 => host.KEY_F10,
            f11 => host.KEY_F11,
            f12 => host.KEY_F12,
        }
    }

    /// The key a number names, or `unknown` for one this version does not.
    pub static fn of(code: int) -> Key {
        if code == host.KEY_CHARACTER { return Key.character }
        if code == host.KEY_ESCAPE { return Key.escape }
        if code == host.KEY_TAB { return Key.tab }
        if code == host.KEY_RETURN { return Key.ret }
        if code == host.KEY_SPACE { return Key.space }
        if code == host.KEY_BACKSPACE { return Key.backspace }
        if code == host.KEY_DELETE { return Key.delete }
        if code == host.KEY_LEFT { return Key.left }
        if code == host.KEY_RIGHT { return Key.right }
        if code == host.KEY_UP { return Key.up }
        if code == host.KEY_DOWN { return Key.down }
        if code == host.KEY_HOME { return Key.home }
        if code == host.KEY_END { return Key.end }
        if code == host.KEY_PAGE_UP { return Key.page_up }
        if code == host.KEY_PAGE_DOWN { return Key.page_down }
        if code == host.KEY_F1 { return Key.f1 }
        if code == host.KEY_F2 { return Key.f2 }
        if code == host.KEY_F3 { return Key.f3 }
        if code == host.KEY_F4 { return Key.f4 }
        if code == host.KEY_F5 { return Key.f5 }
        if code == host.KEY_F6 { return Key.f6 }
        if code == host.KEY_F7 { return Key.f7 }
        if code == host.KEY_F8 { return Key.f8 }
        if code == host.KEY_F9 { return Key.f9 }
        if code == host.KEY_F10 { return Key.f10 }
        if code == host.KEY_F11 { return Key.f11 }
        if code == host.KEY_F12 { return Key.f12 }
        return Key.unknown
    }

    /// Every key, in the order the header numbers them.
    pub static fn all() -> List<Key> {
        var every: List<Key> = []
        var code: int = 0
        for code < host.KEY_COUNT {
            every.push(Key.of(code))
            code = code + 1
        }
        return move every
    }

    /// The host's own word for this key.
    ///
    /// One word, and the same word on every platform — which is the point.
    /// It exists so a suite can ask, because a table of names is exactly the
    /// kind of thing that ends up with two rows sharing a word and nobody
    /// noticing. `tests/input.b` is where it is asked.
    pub fn platform_name() -> Result<string> {
        let code: int = self.code()
        unsafe {
            return host.HostText.read("name the {self.name()} key",
                fn(out: RawPtr<i8>, cap: i32) -> i32 {
                    return host.ctd_key_name(code as i32, out, cap)
                })
        }
    }

    /// cortado's own word for this key, which is the one a program writes.
    ///
    /// `ret` rather than `return`, because `return` is a keyword — and the
    /// word on the wire is still "return", which is what `platform_name`
    /// answers and what a `.bx` attribute spells.
    pub fn name() -> string {
        return match self {
            unknown => "unknown",
            character => "character",
            escape => "escape",
            tab => "tab",
            ret => "return",
            space => "space",
            backspace => "backspace",
            delete => "delete",
            left => "left",
            right => "right",
            up => "up",
            down => "down",
            home => "home",
            end => "end",
            page_up => "page_up",
            page_down => "page_down",
            f1 => "f1",
            f2 => "f2",
            f3 => "f3",
            f4 => "f4",
            f5 => "f5",
            f6 => "f6",
            f7 => "f7",
            f8 => "f8",
            f9 => "f9",
            f10 => "f10",
            f11 => "f11",
            f12 => "f12",
        }
    }
}
