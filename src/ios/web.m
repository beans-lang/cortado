// A browser engine in a rectangle.
//
// WKWebView is part of the system on iOS too, so this host has a real one —
// and it is the same class the Mac uses, which is why this file reads like
// src/mac/web.m with the view types changed. They are still two files: the
// hosts share no header and no translation unit, and a shared one would be a
// fifth place for a platform detail to hide. It is
// the one control in cortado that is a whole other system rather than a
// widget, which is why it has a sub-ABI of its own: navigation, script and
// messages are not properties, and squeezing them into the property bag would
// make every one of them a special case.
//
// **Two things are held here that nothing else in the host holds.** A load's
// serial number, so the started/finished/failed events for one navigation can
// be told apart from the next one's; and a table of texts a token names, so a
// script's answer and a page's message can be read after the event that
// announced them. Both are per web view, and both go when the view does.

#import "internal.h"
#import <WebKit/WebKit.h>

// The delegate and the message handler, in one object because both are about
// the same view and UIKit holds each weakly. `g_targets` keeps it alive, the
// same arrangement the table's data source uses.
@interface CortadoWeb : NSObject <WKNavigationDelegate, WKScriptMessageHandler>
@property (assign) ctd_handle handle;
@property (assign) int64_t serial;
@property (assign) int64_t next_message;
@property (retain) NSMutableDictionary *waiting;
@end

@implementation CortadoWeb

- (id)init {
    self = [super init];
    if (self) {
        _waiting = [[NSMutableDictionary alloc] init];
        // Message tokens count down from below zero so they can never collide
        // with an eval's token, which is the application's own number and may
        // be anything at all.
        _next_message = -1;
    }
    return self;
}

- (void)dealloc {
    [_waiting release];
    [super dealloc];
}

- (void)keep:(NSString *)text under:(int64_t)token {
    [_waiting setObject:text ? text : @""
                 forKey:[NSNumber numberWithLongLong:token]];
}

- (NSString *)takeUnder:(int64_t)token {
    NSNumber *key = [NSNumber numberWithLongLong:token];
    NSString *text = [[[_waiting objectForKey:key] retain] autorelease];
    [_waiting removeObjectForKey:key];
    return text;
}

- (void)webView:(WKWebView *)view didStartProvisionalNavigation:(WKNavigation *)nav {
    _serial = _serial + 1;
    ctd_emit(CTD_EV_WEB_STARTED, _handle, _serial, 0);
}

- (void)webView:(WKWebView *)view didFinishNavigation:(WKNavigation *)nav {
    ctd_emit(CTD_EV_WEB_FINISHED, _handle, _serial, 0);
}

- (void)webView:(WKWebView *)view
        didFailNavigation:(WKNavigation *)nav
        withError:(NSError *)error {
    ctd_emit(CTD_EV_WEB_FAILED, _handle, _serial, (int64_t)[error code]);
}

- (void)webView:(WKWebView *)view
        didFailProvisionalNavigation:(WKNavigation *)nav
        withError:(NSError *)error {
    // A provisional failure is a load that never started — a bad host name, no
    // network — and is the common one. Reported as the same event, because
    // from outside it is the same fact: the page did not arrive.
    ctd_emit(CTD_EV_WEB_FAILED, _handle, _serial, (int64_t)[error code]);
}

- (void)userContentController:(WKUserContentController *)controller
      didReceiveScriptMessage:(WKScriptMessage *)message {
    int64_t token = _next_message;
    _next_message = _next_message - 1;
    id body = [message body];
    [self keep:[body isKindOfClass:[NSString class]]
                ? (NSString *)body : [body description]
         under:token];
    ctd_emit(CTD_EV_WEB_MESSAGE, _handle, 0, token);
}

@end

static WKWebView *ctd_web_of(ctd_handle handle) {
    id object = ctd_resolve(handle);
    if ([object isKindOfClass:[WKWebView class]]) return (WKWebView *)object;
    return nil;
}

static CortadoWeb *ctd_web_keeper(WKWebView *view) {
    id delegate = [view navigationDelegate];
    return [delegate isKindOfClass:[CortadoWeb class]] ? (CortadoWeb *)delegate : nil;
}

UIView *ctd_web_new(void) {
    WKWebViewConfiguration *setup = [[WKWebViewConfiguration alloc] init];
    WKWebView *view = [[WKWebView alloc] initWithFrame:CGRectZero
                                         configuration:setup];
    [setup release];
    return view;
}

void ctd_web_attach(ctd_handle handle, UIView *view) {
    if (![view isKindOfClass:[WKWebView class]]) return;
    CortadoWeb *keeper = [[CortadoWeb alloc] init];
    [keeper setHandle:handle];
    [(WKWebView *)view setNavigationDelegate:keeper];
    [g_targets addObject:keeper];
    [keeper release];
}

ctd_status ctd_web_load(ctd_handle widget, const char *url, int32_t len) {
    if (ctd_has_nul(url, len)) return CTD_ERR_RANGE;
    WKWebView *view = ctd_web_of(widget);
    if (!view) return ctd_resolve(widget) ? CTD_ERR_KIND : CTD_ERR_STALE;
    NSURL *where = [NSURL URLWithString:ctd_string(url, len)];
    // A string NSURL cannot parse is the caller's, and answering "loaded" to
    // it would make the failure arrive later as a navigation error about a
    // page nobody asked for.
    if (!where || ![where scheme]) return CTD_ERR_RANGE;
    [view loadRequest:[NSURLRequest requestWithURL:where]];
    return CTD_OK;
}

ctd_status ctd_web_load_html(ctd_handle widget, const char *html, int32_t html_len,
                             const char *base, int32_t base_len) {
    if (ctd_has_nul(html, html_len) || ctd_has_nul(base, base_len))
        return CTD_ERR_RANGE;
    WKWebView *view = ctd_web_of(widget);
    if (!view) return ctd_resolve(widget) ? CTD_ERR_KIND : CTD_ERR_STALE;
    NSURL *where = base_len > 0 ? [NSURL URLWithString:ctd_string(base, base_len)] : nil;
    [view loadHTMLString:ctd_string(html, html_len) baseURL:where];
    return CTD_OK;
}

ctd_status ctd_web_eval(ctd_handle widget, const char *source, int32_t len,
                        int64_t token) {
    if (ctd_has_nul(source, len)) return CTD_ERR_RANGE;
    WKWebView *view = ctd_web_of(widget);
    if (!view) return ctd_resolve(widget) ? CTD_ERR_KIND : CTD_ERR_STALE;
    CortadoWeb *keeper = ctd_web_keeper(view);
    if (!keeper) return CTD_ERR_PLATFORM;
    ctd_handle handle = widget;
    [view evaluateJavaScript:ctd_string(source, len)
           completionHandler:^(id answer, NSError *error) {
        // WebKit calls this on the main thread, which is where every other
        // event cortado raises comes from. Nothing here hops a queue.
        NSString *text = error ? [error localizedDescription]
                    : [answer isKindOfClass:[NSString class]] ? (NSString *)answer
                    : answer ? [answer description] : @"";
        [keeper keep:text under:token];
        ctd_emit(CTD_EV_WEB_RESULT, handle, error ? 1 : 0, token);
    }];
    return CTD_OK;
}

ctd_status ctd_web_listen(ctd_handle widget, const char *name, int32_t len) {
    if (ctd_has_nul(name, len)) return CTD_ERR_RANGE;
    WKWebView *view = ctd_web_of(widget);
    if (!view) return ctd_resolve(widget) ? CTD_ERR_KIND : CTD_ERR_STALE;
    CortadoWeb *keeper = ctd_web_keeper(view);
    if (!keeper) return CTD_ERR_PLATFORM;
    WKUserContentController *channels =
        [[view configuration] userContentController];
    // Empty closes every channel, which is the only way to say "stop
    // listening" without naming what was opened.
    if (len == 0) {
        [channels removeAllScriptMessageHandlers];
        return CTD_OK;
    }
    NSString *channel = ctd_string(name, len);
    [channels removeScriptMessageHandlerForName:channel];
    [channels addScriptMessageHandler:keeper name:channel];
    return CTD_OK;
}

int32_t ctd_web_take(ctd_handle widget, int64_t token, char *out, int32_t cap) {
    WKWebView *view = ctd_web_of(widget);
    if (!view) return ctd_resolve(widget) ? CTD_ERR_KIND : CTD_ERR_STALE;
    CortadoWeb *keeper = ctd_web_keeper(view);
    if (!keeper) return CTD_ERR_PLATFORM;
    // The two-call shape needs the text to survive the first call, and this
    // one takes it away — so the length call would empty the table before the
    // copy call ran. The text is taken only when there is somewhere to put it.
    if (!out || cap <= 0) {
        NSNumber *key = [NSNumber numberWithLongLong:token];
        NSString *peek = [[keeper waiting] objectForKey:key];
        return ctd_copy_out(peek, NULL, 0);
    }
    return ctd_copy_out([keeper takeUnder:token], out, cap);
}

int32_t ctd_web_url(ctd_handle widget, char *out, int32_t cap) {
    WKWebView *view = ctd_web_of(widget);
    if (!view) return ctd_resolve(widget) ? CTD_ERR_KIND : CTD_ERR_STALE;
    NSURL *where = [view URL];
    return ctd_copy_out(where ? [where absoluteString] : @"", out, cap);
}

int32_t ctd_web_title(ctd_handle widget, char *out, int32_t cap) {
    WKWebView *view = ctd_web_of(widget);
    if (!view) return ctd_resolve(widget) ? CTD_ERR_KIND : CTD_ERR_STALE;
    return ctd_copy_out([view title], out, cap);
}

ctd_status ctd_web_can_go(ctd_handle widget, int32_t back, int32_t *out) {
    WKWebView *view = ctd_web_of(widget);
    if (!view) return ctd_resolve(widget) ? CTD_ERR_KIND : CTD_ERR_STALE;
    if (out) *out = (back ? [view canGoBack] : [view canGoForward]) ? 1 : 0;
    return CTD_OK;
}

ctd_status ctd_web_go(ctd_handle widget, int32_t back) {
    WKWebView *view = ctd_web_of(widget);
    if (!view) return ctd_resolve(widget) ? CTD_ERR_KIND : CTD_ERR_STALE;
    // Nowhere to go is CTD_ERR_RANGE rather than a silent no-op: a program
    // that dimmed its own back button would never ask, and one that did not
    // has a bug worth hearing about.
    if (back ? ![view canGoBack] : ![view canGoForward]) return CTD_ERR_RANGE;
    if (back) [view goBack]; else [view goForward];
    return CTD_OK;
}

ctd_status ctd_web_reload(ctd_handle widget) {
    WKWebView *view = ctd_web_of(widget);
    if (!view) return ctd_resolve(widget) ? CTD_ERR_KIND : CTD_ERR_STALE;
    [view reload];
    return CTD_OK;
}

ctd_status ctd_web_stop(ctd_handle widget) {
    WKWebView *view = ctd_web_of(widget);
    if (!view) return ctd_resolve(widget) ? CTD_ERR_KIND : CTD_ERR_STALE;
    [view stopLoading];
    return CTD_OK;
}
