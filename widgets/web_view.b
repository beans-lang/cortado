// A browser engine in a rectangle.
package widgets

import cortado.host
import cortado.platform

/// A web view.
///
/// `WKWebView` on macOS and iOS, where a browser engine is part of the system.
/// **Not on every platform, and this is the widest gap cortado has**: GTK's
/// engine is WebKitGTK, a separate library a machine may or may not have, and
/// Windows' is WebView2, a redistributable the user has to have installed. A
/// control that worked on a developer's box and was an empty grey rectangle on
/// a user's would be worse than one that says it is not there, so both refuse.
/// Ask `WidgetKind.web_view.available()`, or let `of` refuse with
/// `no_such_control`.
///
/// **Everything here happens later.** A load, a script and a navigation all
/// finish on a later turn of the run loop, as events — `web_started`,
/// `web_finished`, `web_failed`, `web_message`, `web_result` — and the text of
/// a message or a script's answer is read with `take`, keyed by the token the
/// event carried. A control's text has to ride along with its event because
/// the control moves on; a result does not exist until it is ready and nothing
/// can overwrite it, so it waits to be collected.
///
/// **A page cannot reach the program unless it is invited.** `listen` names a
/// channel the page can post to, and a page that posts to an unnamed channel
/// is ignored. A web view with no channel named is a viewer and not a bridge,
/// and that is what a fresh one is.
pub class WebView extends Widget {
    pub fn init() {
        super.init(WidgetKind.web_view)
    }

    pub static fn of() -> Result<WebView> {
        WidgetKind.web_view.demand()?
        return ok(new WebView())
    }

    /// Whether this platform has a browser engine at all.
    ///
    /// The same answer as `WidgetKind.web_view.available()`, asked the other
    /// way: a program that wants to lay out a different screen entirely reads
    /// better asking a capability than asking a widget kind.
    pub static fn offered() -> bool {
        return platform.Capability.web.available()
    }

    pub fn load(url: string) -> Result<bool> {
        let bytes: Bytes = host.HostText.encode(url, "load a page")?
        unsafe {
            return host.check(
                host.ctd_web_load(self.handle().raw, host.HostText.pointer(bytes),
                                  bytes.len() as i32) as int,
                "load {url}")
        }
    }

    /// Shows markup directly. `base` is what relative links resolve against,
    /// and may be empty.
    pub fn load_html(html: string, base: string) -> Result<bool> {
        let body: Bytes = host.HostText.encode(html, "show markup")?
        let root: Bytes = host.HostText.encode(base, "show markup")?
        unsafe {
            return host.check(
                host.ctd_web_load_html(self.handle().raw,
                                       host.HostText.pointer(body), body.len() as i32,
                                       host.HostText.pointer(root), root.len() as i32) as int,
                "show markup")
        }
    }

    /// Runs script in the page. The answer arrives as `web_result` carrying
    /// `token`, and is read with `collect`.
    pub fn eval(source: string, token: int) -> Result<bool> {
        let bytes: Bytes = host.HostText.encode(source, "run script")?
        unsafe {
            return host.check(
                host.ctd_web_eval(self.handle().raw, host.HostText.pointer(bytes),
                                  bytes.len() as i32, token as i64) as int,
                "run script")
        }
    }

    /// Opens a channel the page can post to by name. An empty name closes
    /// every channel.
    pub fn listen(channel: string) -> Result<bool> {
        let bytes: Bytes = host.HostText.encode(channel, "open a channel")?
        unsafe {
            return host.check(
                host.ctd_web_listen(self.handle().raw, host.HostText.pointer(bytes),
                                    bytes.len() as i32) as int,
                "open the channel {channel}")
        }
    }

    /// The text an event's token names, once.
    ///
    /// Collecting it clears it: reading twice answers `""`. A buffer nobody
    /// clears is a leak with a name.
    ///
    /// (`take` is a reserved word in Beans, which is why this is not called
    /// that — the ABI's own entry point is still `ctd_web_take`.)
    pub fn collect(token: int) -> Result<string> {
        unsafe {
            return host.HostText.read("collect what token {token} named",
                fn(out: RawPtr<i8>, cap: i32) -> i32 {
                    return host.ctd_web_take(self.handle().raw, token as i64, out, cap)
                })
        }
    }

    pub fn url() -> Result<string> {
        unsafe {
            return host.HostText.read("read where a web view is",
                fn(out: RawPtr<i8>, cap: i32) -> i32 {
                    return host.ctd_web_url(self.handle().raw, out, cap)
                })
        }
    }

    pub fn title() -> Result<string> {
        unsafe {
            return host.HostText.read("read what a page calls itself",
                fn(out: RawPtr<i8>, cap: i32) -> i32 {
                    return host.ctd_web_title(self.handle().raw, out, cap)
                })
        }
    }

    pub fn can_go_back() -> Result<bool> {
        return self.can_go(true)
    }

    pub fn can_go_forward() -> Result<bool> {
        return self.can_go(false)
    }

    fn can_go(back: bool) -> Result<bool> {
        let scratch: host.HostScratch = host.HostScratch.instance
        var able: i32 = 0
        unsafe {
            let slot: RawPtr<i32> = RawPtr.from_address(scratch.ints.address())
            host.check(host.ctd_web_can_go(self.handle().raw,
                                           if back { 1 } else { 0 }, slot) as int,
                       "read whether a web view can go back")?
            able = slot.read()
        }
        return ok(able != 0)
    }

    /// Goes back, or refuses with `out_of_range` when there is nowhere to go.
    pub fn go_back() -> Result<bool> {
        return self.go(true)
    }

    pub fn go_forward() -> Result<bool> {
        return self.go(false)
    }

    fn go(back: bool) -> Result<bool> {
        unsafe {
            return host.check(
                host.ctd_web_go(self.handle().raw, if back { 1 } else { 0 }) as int,
                "go back or forward in a web view")
        }
    }

    pub fn reload() -> Result<bool> {
        unsafe {
            return host.check(host.ctd_web_reload(self.handle().raw) as int,
                              "reload a page")
        }
    }

    pub fn stop() -> Result<bool> {
        unsafe {
            return host.check(host.ctd_web_stop(self.handle().raw) as int,
                              "stop loading a page")
        }
    }
}
