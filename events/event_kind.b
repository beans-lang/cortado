// What happened.
package events

import cortado.host

/// The kinds of event a cortado program can receive.
///
/// One list for every platform, including the mobile ones cortado does not
/// build for yet. `app_background` and `low_memory` never fire on a desktop,
/// and that is deliberate: a program written today against the full list runs
/// unchanged on a phone later, instead of being rewritten around a lifecycle
/// it was never told about.
///
/// Pointer events cover a mouse and a finger with one shape for the same
/// reason. Bolting touch onto a mouse-only API afterwards is the classic way
/// a toolkit ends up with two event systems that disagree.
pub enum EventKind {
    activate
    value_changed
    text_commit
    selection
    pointer_down
    pointer_up
    pointer_move
    key_down
    key_up
    focus
    blur
    surface_resized
    surface_close
    appearance
    scale_changed
    post
    app_launched
    app_foreground
    app_background
    app_will_quit
    low_memory
    command
    frame
    anim_done
    /// The user answered a permission prompt. `token` echoes the request's.
    permission
    /// A popover went away, whether the program closed it or the user clicked
    /// elsewhere. `target` is the popover.
    dismiss
    /// A web view began a load. `index` is a serial number.
    web_started
    /// It finished. `index` is the same serial.
    web_finished
    /// It did not. `index` is the serial, `token` the platform's error code.
    web_failed
    /// The page sent something. `token` keys the text; `WebView.collect` reads it.
    web_message
    /// A script answered. `token` echoes the call's; `WebView.collect` reads it.
    web_result
    /// What this machine can reach changed. `index` is the new
    /// `device.NetworkPath`, `position.x` the flags.
    ///
    /// Registering for it is also what starts the platform's own monitor,
    /// which is why there is no separate watch call.
    net_changed
    /// What is running the machine changed, or the battery moved. `index` is
    /// the new `device.PowerSource`, `position.x` the charge — or -1 where
    /// there is no battery to have one.
    power_changed
    /// Where the machine is. `position` is the latitude and longitude,
    /// `size.width` the accuracy in metres and `size.height` the heading — or
    /// -1 where nobody knows, which is every machine standing still.
    location
    /// Something was seen over Bluetooth, or one that was seen changed.
    /// `index` is its row and `position.x` the signal strength.
    ble_found
    /// A peripheral was connected or dropped. `index` is the row, `token` 1 or
    /// 0 for which.
    ble_link
    /// A camera or microphone appeared or went. `index` is how many there are.
    capture_devices
    /// A picture of the screen is ready, or was not. `token` echoes the
    /// request's and `index` is the byte length waiting — 0 where it failed.
    screen_frame
    unknown

    pub fn name() -> string {
        return match self {
            activate => "activate",
            value_changed => "value_changed",
            text_commit => "text_commit",
            selection => "selection",
            pointer_down => "pointer_down",
            pointer_up => "pointer_up",
            pointer_move => "pointer_move",
            key_down => "key_down",
            key_up => "key_up",
            focus => "focus",
            blur => "blur",
            surface_resized => "surface_resized",
            surface_close => "surface_close",
            appearance => "appearance",
            scale_changed => "scale_changed",
            post => "post",
            app_launched => "app_launched",
            app_foreground => "app_foreground",
            app_background => "app_background",
            app_will_quit => "app_will_quit",
            low_memory => "low_memory",
            command => "command",
            frame => "frame",
            anim_done => "anim_done",
            permission => "permission",
            dismiss => "dismiss",
            web_started => "web_started",
            web_finished => "web_finished",
            web_failed => "web_failed",
            web_message => "web_message",
            web_result => "web_result",
            net_changed => "net_changed",
            power_changed => "power_changed",
            location => "location",
            ble_found => "ble_found",
            ble_link => "ble_link",
            capture_devices => "capture_devices",
            screen_frame => "screen_frame",
            unknown => "unknown",
        }
    }

    /// The integer this kind is keyed by. The ABI's own number, so a router
    /// lookup needs no translation table of its own.
    pub fn name_code() -> int {
        return match self {
            activate => host.EV_ACTIVATE,
            value_changed => host.EV_VALUE_CHANGED,
            text_commit => host.EV_TEXT_COMMIT,
            selection => host.EV_SELECTION,
            pointer_down => host.EV_POINTER_DOWN,
            pointer_up => host.EV_POINTER_UP,
            pointer_move => host.EV_POINTER_MOVE,
            key_down => host.EV_KEY_DOWN,
            key_up => host.EV_KEY_UP,
            focus => host.EV_FOCUS,
            blur => host.EV_BLUR,
            surface_resized => host.EV_SURFACE_RESIZED,
            surface_close => host.EV_SURFACE_CLOSE,
            appearance => host.EV_APPEARANCE,
            scale_changed => host.EV_SCALE_CHANGED,
            post => host.EV_POST,
            app_launched => host.EV_APP_LAUNCHED,
            app_foreground => host.EV_APP_FOREGROUND,
            app_background => host.EV_APP_BACKGROUND,
            app_will_quit => host.EV_APP_WILL_QUIT,
            low_memory => host.EV_LOW_MEMORY,
            command => host.EV_COMMAND,
            frame => host.EV_FRAME,
            anim_done => host.EV_ANIM_DONE,
            permission => host.EV_PERMISSION,
            dismiss => host.EV_DISMISS,
            web_started => host.EV_WEB_STARTED,
            web_finished => host.EV_WEB_FINISHED,
            web_failed => host.EV_WEB_FAILED,
            web_message => host.EV_WEB_MESSAGE,
            web_result => host.EV_WEB_RESULT,
            net_changed => host.EV_NET_CHANGED,
            power_changed => host.EV_POWER_CHANGED,
            location => host.EV_LOCATION,
            ble_found => host.EV_BLE_FOUND,
            ble_link => host.EV_BLE_LINK,
            capture_devices => host.EV_CAPTURE_DEVICES,
            screen_frame => host.EV_SCREEN_FRAME,
            unknown => 0,
        }
    }

    /// Maps a raw code from the host. An unrecognized code becomes `unknown`
    /// rather than a panic: a host built against a newer header is a version
    /// mismatch to report, not a reason to take the program down.
    pub static fn of(code: int) -> EventKind {
        if code == host.EV_ACTIVATE { return EventKind.activate }
        if code == host.EV_VALUE_CHANGED { return EventKind.value_changed }
        if code == host.EV_TEXT_COMMIT { return EventKind.text_commit }
        if code == host.EV_SELECTION { return EventKind.selection }
        if code == host.EV_POINTER_DOWN { return EventKind.pointer_down }
        if code == host.EV_POINTER_UP { return EventKind.pointer_up }
        if code == host.EV_POINTER_MOVE { return EventKind.pointer_move }
        if code == host.EV_KEY_DOWN { return EventKind.key_down }
        if code == host.EV_KEY_UP { return EventKind.key_up }
        if code == host.EV_FOCUS { return EventKind.focus }
        if code == host.EV_BLUR { return EventKind.blur }
        if code == host.EV_SURFACE_RESIZED { return EventKind.surface_resized }
        if code == host.EV_SURFACE_CLOSE { return EventKind.surface_close }
        if code == host.EV_APPEARANCE { return EventKind.appearance }
        if code == host.EV_SCALE_CHANGED { return EventKind.scale_changed }
        if code == host.EV_POST { return EventKind.post }
        if code == host.EV_APP_LAUNCHED { return EventKind.app_launched }
        if code == host.EV_APP_FOREGROUND { return EventKind.app_foreground }
        if code == host.EV_APP_BACKGROUND { return EventKind.app_background }
        if code == host.EV_APP_WILL_QUIT { return EventKind.app_will_quit }
        if code == host.EV_LOW_MEMORY { return EventKind.low_memory }
        if code == host.EV_COMMAND { return EventKind.command }
        if code == host.EV_FRAME { return EventKind.frame }
        if code == host.EV_ANIM_DONE { return EventKind.anim_done }
        if code == host.EV_PERMISSION { return EventKind.permission }
        if code == host.EV_DISMISS { return EventKind.dismiss }
        if code == host.EV_WEB_STARTED { return EventKind.web_started }
        if code == host.EV_WEB_FINISHED { return EventKind.web_finished }
        if code == host.EV_WEB_FAILED { return EventKind.web_failed }
        if code == host.EV_WEB_MESSAGE { return EventKind.web_message }
        if code == host.EV_WEB_RESULT { return EventKind.web_result }
        if code == host.EV_NET_CHANGED { return EventKind.net_changed }
        if code == host.EV_POWER_CHANGED { return EventKind.power_changed }
        if code == host.EV_LOCATION { return EventKind.location }
        if code == host.EV_BLE_FOUND { return EventKind.ble_found }
        if code == host.EV_BLE_LINK { return EventKind.ble_link }
        if code == host.EV_CAPTURE_DEVICES { return EventKind.capture_devices }
        if code == host.EV_SCREEN_FRAME { return EventKind.screen_frame }
        return EventKind.unknown
    }
}
