// A menu, and the commands in it.
package surface

import cortado.host

/// A menu: a list of commands, separators and submenus.
///
/// Built once at startup and installed as the application's menu bar, or
/// nested inside another menu. The commands in it are identified by a **token**
/// — a number you choose — which comes back on the `command` event. cortado
/// never interprets a token, so key your command table however suits you.
///
/// ```beans
/// var file: surface.Menu = surface.Menu.of("File")?
/// file.add("New", "mod+n", surface.CommandRole.none, NEW_ORDER)?
/// file.separator()?
/// file.add("", "", surface.CommandRole.close, 0)?
///
/// var bar: surface.Menu = surface.Menu.of("")?
/// bar.submenu(app_menu)?
/// bar.submenu(file)?
/// bar.install()?
/// ```
///
/// The first submenu of a menu bar is the application menu on macOS, whatever
/// it is called — AppKit takes the first one and renames it after the running
/// application. That is a platform rule cortado does not hide, because hiding
/// it would mean reordering somebody's menus behind their back.
pub class Menu {
    slot: host.Handle = host.Handle.none()

    fn init(slot: host.Handle) {
        self.slot = slot
    }

    pub static fn of(title: string) -> Result<Menu> {
        let buffer: Bytes = host.HostText.encode(title, "name a menu")?
        unsafe {
            let made: u64 = host.ctd_menu_new(host.HostText.pointer(buffer),
                                              buffer.len() as i32)
            if made == 0 {
                return err("the platform would not make a menu called \"{title}\"", "platform")
            }
            return ok(new Menu(host.Handle.of(made)))
        }
    }

    pub fn handle() -> host.Handle {
        return self.slot
    }

    /// Adds a command.
    ///
    /// `title` and `key` are advisory when `role` is not `none`: the platform
    /// uses its own word and its own shortcut, so a menu reads right in the
    /// language and with the keys a user of that system expects.
    ///
    /// `key` is portable — `"mod+s"`, `"mod+shift+n"` — where `mod` is Command
    /// on macOS and Control elsewhere.
    pub fn add(title: string, key: string, role: CommandRole, token: int) -> Result<bool> {
        let shown: Bytes = host.HostText.encode(title, "add a menu item")?
        let shortcut: Bytes = host.HostText.encode(key, "set a menu item's shortcut")?
        unsafe {
            return host.check(
                host.ctd_menu_add_item(self.slot.raw,
                                       host.HostText.pointer(shown), shown.len() as i32,
                                       host.HostText.pointer(shortcut), shortcut.len() as i32,
                                       role.code() as i32, token as i64) as int,
                "add \"{title}\" to a menu")
        }
    }

    pub fn separator() -> Result<bool> {
        unsafe {
            return host.check(host.ctd_menu_add_separator(self.slot.raw) as int,
                              "add a separator to a menu")
        }
    }

    pub fn submenu(child: Menu) -> Result<bool> {
        unsafe {
            return host.check(
                host.ctd_menu_add_submenu(self.slot.raw, child.handle().raw) as int,
                "nest a menu inside a menu")
        }
    }

    pub fn count() -> Result<int> {
        let scratch: host.HostScratch = host.HostScratch.instance
        var total: i32 = 0
        unsafe {
            let out: RawPtr<i32> = RawPtr.from_address(scratch.ints.address())
            host.check(host.ctd_menu_item_count(self.slot.raw, out) as int,
                       "count a menu's items")?
            total = out.read()
        }
        return ok(total as int)
    }

    /// The title the platform ended up showing — for a role, the platform's
    /// own word rather than the one that was passed in. A separator reads "-".
    pub fn title_at(index: int) -> Result<string> {
        let raw: u64 = self.slot.raw
        let at: i32 = index as i32
        return host.HostText.read(
            "read the title of menu item {index}",
            fn(out: RawPtr<i8>, cap: i32) -> i32 {
                unsafe { return host.ctd_menu_item_title(raw, at, out, cap) }
            })
    }

    /// The shortcut the platform ended up assigning, in the same portable
    /// spelling `add` takes.
    pub fn key_at(index: int) -> Result<string> {
        let raw: u64 = self.slot.raw
        let at: i32 = index as i32
        return host.HostText.read(
            "read the shortcut of menu item {index}",
            fn(out: RawPtr<i8>, cap: i32) -> i32 {
                unsafe { return host.ctd_menu_item_key(raw, at, out, cap) }
            })
    }

    /// Installs this menu as the application's menu bar.
    ///
    /// Refused where the platform has no such thing — ask
    /// `platform.Capability.menu_bar` first if you support one that does not.
    pub fn install() -> Result<bool> {
        unsafe {
            return host.check(host.ctd_menu_set_bar(self.slot.raw) as int,
                              "install a menu bar")
        }
    }

    /// Greys a command out, or brings it back. Found by token anywhere under
    /// this menu, submenus included: a token names a command, and where it was
    /// placed is not something the application should have to remember.
    pub fn set_enabled(token: int, on: bool) -> Result<bool> {
        unsafe {
            return host.check(
                host.ctd_menu_set_enabled(self.slot.raw, token as i64,
                                          if on { 1 } else { 0 }) as int,
                "enable menu command {token}")
        }
    }

    /// Chooses a command the way a user does — through the platform's own
    /// dispatch, so a role reaches the responder chain exactly as it would.
    ///
    /// Public API and not only a test hook: a program that offers the same
    /// command from a toolbar button should run it through here rather than
    /// calling its handler, so the command is disabled in both places at once.
    pub fn invoke(token: int) -> Result<bool> {
        unsafe {
            return host.check(host.ctd_menu_invoke(self.slot.raw, token as i64) as int,
                              "choose menu command {token}")
        }
    }
}
