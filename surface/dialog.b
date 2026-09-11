// Asking the user something.
package surface

import cortado.host

/// What a dialog asks for.
pub enum DialogKind {
    /// Says something, with one button.
    message
    /// Asks something, with a confirm and a cancel.
    confirm
    /// Chooses an existing file.
    open_file
    /// Chooses a name to write.
    save_file

    pub fn code() -> int {
        return match self {
            message => host.DLG_MESSAGE,
            confirm => host.DLG_CONFIRM,
            open_file => host.DLG_OPEN,
            save_file => host.DLG_SAVE,
        }
    }

    pub fn name() -> string {
        return match self {
            message => "message",
            confirm => "confirm",
            open_file => "open_file",
            save_file => "save_file",
        }
    }
}

/// Opens a dialog and answers later.
///
/// **Every dialog here is asynchronous, and that is not a style cortado chose
/// — it is what the platforms do.** A macOS sheet runs its own loop and calls
/// back; a GTK dialog is asynchronous by construction; on iOS a modal view
/// controller has no synchronous form at all. A blocking `open_file()` would
/// have to spin an inner event loop, which re-enters everything — including
/// the render the call came out of, and the handler that started it.
///
/// So `ask` takes a token and the answer arrives as a `post` event carrying
/// that token. The shape is a little more work to write and it is the only one
/// that does not deadlock:
///
/// ```beans
/// app.router.on(host.Handle.none(), events.EventKind.post,
///     fn(event: events.UiEvent) {
///         if event.token != SAVE_AS { return }
///         if event.index != 0 { return }          // cancelled
///         self.write_to(event.text)
///     })
/// surface.Dialog.ask(window, surface.DialogKind.save_file,
///                    "Save order", "Choose a file", SAVE_AS)?
/// ```
///
/// `index` is 0 for the confirming button and 1 for a cancel; `text` carries
/// the chosen path for a file dialog and is empty otherwise.
///
/// ### With no surface to attach to
///
/// **A dialog always answers.** It needs a window that is actually on screen
/// to hang from; with none — a headless run, or a window that has not been
/// shown yet — a message answers its default button and a file dialog answers
/// a cancel, immediately.
///
/// The alternative is worse than it sounds. A sheet attached to an unshown
/// window runs no completion handler at all, so the caller waits on a token
/// that never arrives: a hang, and the worst failure an asynchronous API can
/// have. Answering means the caller's code path is the same with and without a
/// display, which is what makes a program that uses dialogs testable at all.
pub class Dialog {
    pub static fn ask(parent: Surface, kind: DialogKind, title: string,
                      body: string, token: int) -> Result<bool> {
        return Dialog.open(parent.handle(), kind, title, body, token)
    }

    /// The same, with no surface to attach to.
    pub static fn ask_free(kind: DialogKind, title: string, body: string,
                           token: int) -> Result<bool> {
        return Dialog.open(host.Handle.none(), kind, title, body, token)
    }

    static fn open(parent: host.Handle, kind: DialogKind, title: string,
                   body: string, token: int) -> Result<bool> {
        let heading: Bytes = host.HostText.encode(title, "title a dialog")?
        let detail: Bytes = host.HostText.encode(body, "write a dialog's message")?
        unsafe {
            return host.check(
                host.ctd_dialog_open(parent.raw, kind.code() as i32,
                                     host.HostText.pointer(heading), heading.len() as i32,
                                     host.HostText.pointer(detail), detail.len() as i32,
                                     token as i64) as int,
                "open a {kind.name()} dialog")
        }
    }
}
