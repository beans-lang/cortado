// Words that go somewhere.
package widgets

import cortado.host

/// A link.
///
/// `GtkLinkButton` and a `SysLink` are real controls; AppKit and UIKit have
/// none, so the Mac uses an `NSTextField` holding an attributed string with a
/// link attribute — which is what gives the blue underline, the pointing-hand
/// cursor and the click that opens the URL in the user's own browser with the
/// user's own handler registrations — and the phone uses a `UIButton` the host
/// opens for.
///
/// **A link opens its URL and raises nothing.** That is a decision rather than
/// an oversight. The four platforms disagree about who follows a link, and
/// none of them lets a program intercept the click and route it somewhere
/// else, so cortado does not promise an event it could raise on only some of
/// them. A program that wants to handle the click itself wants a `Button` with
/// the words in its title — a different control, which says so.
pub class Link extends Widget {
    pub fn init() {
        super.init(WidgetKind.link)
    }

    /// `words` is what is shown, `url` is where it goes.
    pub static fn of(words: string, url: string) -> Result<Link> {
        WidgetKind.link.demand()?
        var link: Link = new Link()
        // The target first, because on two hosts the words and the target are
        // one string and writing the words alone would drop the other half.
        link.set_url(url)?
        link.set_words(words)?
        return ok(link)
    }

    pub fn set_words(words: string) -> Result<bool> {
        return self.set_text_raw(words)
    }

    pub fn words() -> Result<string> {
        return self.text_raw()
    }

    /// Where it goes. A string the platform cannot read as a URL is
    /// `out_of_range` rather than a link that does nothing when it is clicked.
    pub fn set_url(url: string) -> Result<bool> {
        return self.set_string(host.S_URL, url, "set where a link goes")
    }

    pub fn url() -> Result<string> {
        return self.string_at(host.S_URL, "read where a link goes")
    }

    pub override fn display_text() -> Result<string> {
        return self.words()
    }
}
