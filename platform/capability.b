// What this platform can do.
package platform

import cortado.host

/// Something a platform may or may not offer.
///
/// cortado's promise is that the same program runs everywhere, not that every
/// platform grows the features of every other. macOS has one menu bar for the
/// whole application and Windows has one per window; a phone has neither. A
/// program that wants to do the right thing on each asks first.
///
/// The alternative — quietly doing nothing where a feature is missing — is
/// worse than it sounds. It turns "my menu never appears" into a bug with no
/// error, no log line and nothing to search for.
pub enum Capability {
    menu_bar
    window_menu
    multi_surface
    resizable
    file_dialog
    snapshot
    gpu
    /// A row of commands attached to a window.
    ///
    /// Described by a menu — the same handle and the same tokens, so a program
    /// with one command table needs no second one. A platform with no menus
    /// therefore has no toolbar either, which is why iOS answers no: what is
    /// missing there is not the strip, it is anything to describe it with.
    toolbar
    /// A small window anchored to a control.
    ///
    /// `NSPopover` and `GtkPopover` are real. Windows has no such control —
    /// every application makes a layered window and captures the mouse — and
    /// UIKit's is a presentation that becomes a full-screen sheet on a phone,
    /// which is a different control with a different dismissal.
    popover
    /// A browser engine in a rectangle.
    ///
    /// The widest gap cortado has. WKWebView is part of the system on macOS
    /// and iOS; GTK's engine is WebKitGTK, a separate library, and Windows' is
    /// WebView2, a redistributable the user has to have installed.
    web
    /// The system's own icon set, named by role — see `widgets.SystemIcon`.
    ///
    /// Every platform here answers yes, and that is not the same as every
    /// role being available: what this asks is whether there is a set at all,
    /// and `SystemIcon.available()` is what asks about one icon. Windows has
    /// an icon set and no picture for "run".
    icons
    /// Whether anything is reachable, and over what.
    ///
    /// Not privacy-gated on any platform here, which is what lets it be asked
    /// from an ordinary program and an ordinary test — unlike everything
    /// behind `device.Permission`.
    network
    /// What is running the machine, how full the battery is, and how hot it
    /// is.
    ///
    /// Every platform answers yes, and that is not the same as every question
    /// having an answer: a machine with no battery refuses `charge`, and only
    /// Apple's platforms have a scale for heat. What this asks is whether
    /// there is anything to ask.
    power
    /// Where the machine is.
    ///
    /// Gated: a program that asks without a bundle and a declared reason is
    /// refused, and one that reached the framework without them would be
    /// terminated rather than refused.
    location
    /// What is nearby, over Bluetooth. Gated the same way.
    bluetooth
    /// Cameras and microphones. Gated the same way, and separately for each:
    /// a program that only wants to hear should not be asking to see.
    capture
    /// Recording the screen.
    ///
    /// No on a phone, and not for want of trying: ReplayKit is a broadcast the
    /// person starts from Control Centre, not a screen a program can read.
    screen

    fn code() -> int {
        return match self {
            menu_bar => host.CAP_MENU_BAR,
            window_menu => host.CAP_WINDOW_MENU,
            multi_surface => host.CAP_MULTI_SURFACE,
            resizable => host.CAP_RESIZABLE,
            file_dialog => host.CAP_FILE_DIALOG,
            snapshot => host.CAP_SNAPSHOT,
            gpu => host.CAP_GPU,
            toolbar => host.CAP_TOOLBAR,
            popover => host.CAP_POPOVER,
            web => host.CAP_WEB,
            icons => host.CAP_ICONS,
            network => host.CAP_NETWORK,
            power => host.CAP_POWER,
            location => host.CAP_LOCATION,
            bluetooth => host.CAP_BLUETOOTH,
            capture => host.CAP_CAPTURE,
            screen => host.CAP_SCREEN,
        }
    }

    pub fn name() -> string {
        return match self {
            menu_bar => "menu_bar",
            window_menu => "window_menu",
            multi_surface => "multi_surface",
            resizable => "resizable",
            file_dialog => "file_dialog",
            snapshot => "snapshot",
            gpu => "gpu",
            toolbar => "toolbar",
            popover => "popover",
            web => "web",
            icons => "icons",
            network => "network",
            power => "power",
            location => "location",
            bluetooth => "bluetooth",
            capture => "capture",
            screen => "screen",
        }
    }

    /// Whether the platform running this program offers it.
    pub fn available() -> bool {
        unsafe {
            return host.ctd_capability(self.code() as i32) == 1
        }
    }
}
