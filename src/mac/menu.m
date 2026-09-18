// Menus, and the roles that make them portable.
//
// A command with a role is placed, named and keyed by the platform; one
// without goes where the application puts it.

#import "internal.h"

// ---------------------------------------------------------------------- menus

// One menu item's identity, carried on the NSMenuItem itself.
//
// AppKit gives a menu item one `tag`, an NSInteger, and that is exactly what is
// needed: the application's own token, handed back on CTD_EV_COMMAND. Nothing
// else about the item has to be remembered.

@implementation CortadoCommand
- (void)chose:(id)sender {
    if (![sender isKindOfClass:[NSMenuItem class]]) return;
    ctd_event event;
    memset(&event, 0, sizeof event);
    event.kind = CTD_EV_COMMAND;
    event.token = (int64_t)[(NSMenuItem *)sender tag];
    if (g_sink) g_sink(g_sink_context, &event);
}
@end

// A portable shortcut description — "mod+shift+s" — as the key and the
// modifier mask AppKit wants.
//
// `mod` is Command here and Control elsewhere, which is the whole reason the
// description is portable rather than a literal key. An unrecognised word is
// ignored rather than refused: a shortcut that did not attach is a menu item
// that still works, and refusing the whole menu over one would be worse.
static NSString *ctd_shortcut(NSString *spec, NSEventModifierFlags *mask) {
    *mask = 0;
    if ([spec length] == 0) return @"";
    NSArray *parts = [[spec lowercaseString] componentsSeparatedByString:@"+"];
    NSString *key = @"";
    for (NSString *part in parts) {
        if ([part isEqualToString:@"mod"] || [part isEqualToString:@"cmd"]) {
            *mask |= NSEventModifierFlagCommand;
        } else if ([part isEqualToString:@"shift"]) {
            *mask |= NSEventModifierFlagShift;
        } else if ([part isEqualToString:@"alt"] || [part isEqualToString:@"opt"]) {
            *mask |= NSEventModifierFlagOption;
        } else if ([part isEqualToString:@"ctrl"] || [part isEqualToString:@"control"]) {
            *mask |= NSEventModifierFlagControl;
        } else {
            key = part;
        }
    }
    // AppKit expects the character produced by Return, not the word
    // "return". A literal word leaves the menu label intact but never fires.
    if ([key isEqualToString:@"return"] || [key isEqualToString:@"enter"])
        return @"\r";
    return key;
}

// The shortcut a menu item ended up with, in the portable spelling.
static NSString *ctd_shortcut_text(NSMenuItem *item) {
    NSString *key = [item keyEquivalent];
    if ([key length] == 0) return @"";
    NSMutableArray *parts = [NSMutableArray array];
    NSEventModifierFlags mask = [item keyEquivalentModifierMask];
    if (mask & NSEventModifierFlagCommand) [parts addObject:@"mod"];
    if (mask & NSEventModifierFlagControl) [parts addObject:@"ctrl"];
    if (mask & NSEventModifierFlagOption)  [parts addObject:@"alt"];
    if (mask & NSEventModifierFlagShift)   [parts addObject:@"shift"];
    [parts addObject:[key isEqualToString:@"\r"] ? @"return" : [key lowercaseString]];
    return [parts componentsJoinedByString:@"+"];
}

// What the platform calls a role, and what key it gives it.
//
// The titles are Apple's own words — "Quit Coffee", not "Exit" — because a
// menu that said the wrong word would be the one thing a user notices
// immediately. The selector matters more: Cut, Copy, Paste, Undo and Select
// All go to `nil`, so AppKit walks the responder chain and the focused text
// field handles them. Wiring them to a handler of ours would break editing in
// every system control in the window.
static SEL ctd_role_selector(int32_t role) {
    switch (role) {
        case CTD_CMD_HIDE:       return @selector(hide:);
        case CTD_CMD_QUIT:       return @selector(terminate:);
        case CTD_CMD_UNDO:       return @selector(undo:);
        case CTD_CMD_REDO:       return @selector(redo:);
        case CTD_CMD_CUT:        return @selector(cut:);
        case CTD_CMD_COPY:       return @selector(copy:);
        case CTD_CMD_PASTE:      return @selector(paste:);
        case CTD_CMD_SELECT_ALL: return @selector(selectAll:);
        case CTD_CMD_CLOSE:      return @selector(performClose:);
        case CTD_CMD_MINIMIZE:   return @selector(performMiniaturize:);
        case CTD_CMD_FULLSCREEN: return @selector(toggleFullScreen:);
        default:                 return NULL;
    }
}

static NSString *ctd_role_title(int32_t role, NSString *fallback) {
    switch (role) {
        case CTD_CMD_ABOUT:       return @"About";
        case CTD_CMD_PREFERENCES: return @"Settings…";
        case CTD_CMD_QUIT:        return @"Quit";
        case CTD_CMD_HIDE:        return @"Hide";
        case CTD_CMD_UNDO:        return @"Undo";
        case CTD_CMD_REDO:        return @"Redo";
        case CTD_CMD_CUT:         return @"Cut";
        case CTD_CMD_COPY:        return @"Copy";
        case CTD_CMD_PASTE:       return @"Paste";
        case CTD_CMD_SELECT_ALL:  return @"Select All";
        case CTD_CMD_CLOSE:       return @"Close";
        case CTD_CMD_MINIMIZE:    return @"Minimize";
        case CTD_CMD_FULLSCREEN:  return @"Enter Full Screen";
        default:                  return fallback;
    }
}

static NSString *ctd_role_key(int32_t role, NSString *fallback) {
    switch (role) {
        case CTD_CMD_PREFERENCES: return @"mod+,";
        case CTD_CMD_QUIT:        return @"mod+q";
        case CTD_CMD_HIDE:        return @"mod+h";
        case CTD_CMD_UNDO:        return @"mod+z";
        case CTD_CMD_REDO:        return @"mod+shift+z";
        case CTD_CMD_CUT:         return @"mod+x";
        case CTD_CMD_COPY:        return @"mod+c";
        case CTD_CMD_PASTE:       return @"mod+v";
        case CTD_CMD_SELECT_ALL:  return @"mod+a";
        case CTD_CMD_CLOSE:       return @"mod+w";
        case CTD_CMD_MINIMIZE:    return @"mod+m";
        case CTD_CMD_FULLSCREEN:  return @"mod+ctrl+f";
        default:                  return fallback;
    }
}

static NSMenu *ctd_menu_of(ctd_handle handle) {
    id object = ctd_resolve(handle);
    if ([object isKindOfClass:[NSMenu class]]) return (NSMenu *)object;
    return nil;
}

ctd_handle ctd_menu_new(const char *title, int32_t len) {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:ctd_string(title, len)];
    // A menu enables its own items by asking their targets; cortado's items
    // are enabled explicitly, so automatic validation is off and an item stays
    // as the application set it.
    [menu setAutoenablesItems:NO];
    ctd_handle handle = ctd_track(menu, CTD_W_CONTAINER);
    [menu release];
    return handle;
}

ctd_status ctd_menu_add_item(ctd_handle handle, const char *title, int32_t title_len,
                             const char *key, int32_t key_len,
                             int32_t role, int64_t token) {
    if (ctd_has_nul(title, title_len) || ctd_has_nul(key, key_len))
        return CTD_ERR_RANGE;
    NSMenu *menu = ctd_menu_of(handle);
    if (!menu) return ctd_resolve(handle) ? CTD_ERR_KIND : CTD_ERR_STALE;
    if (role < 0 || role > CTD_CMD_FULLSCREEN) return CTD_ERR_RANGE;

    NSString *requested = ctd_string(title, title_len);
    NSString *shown = ctd_role_title(role, requested);
    // The app host uses token zero for its standard macOS commands. Keep the
    // app name in those titles; an explicit application command can still use
    // the role's ordinary platform title and its own token.
    if (token == 0 && [requested length] > 0 &&
        (role == CTD_CMD_ABOUT || role == CTD_CMD_HIDE || role == CTD_CMD_QUIT))
        shown = requested;
    NSString *spec = ctd_role_key(role, ctd_string(key, key_len));
    NSEventModifierFlags mask = 0;
    NSString *equivalent = ctd_shortcut(spec, &mask);

    SEL action = ctd_role_selector(role);
    if (role == CTD_CMD_ABOUT && token == 0)
        action = @selector(orderFrontStandardAboutPanel:);
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:shown
                                                 action:action ? action : @selector(chose:)
                                          keyEquivalent:equivalent];
    [item setKeyEquivalentModifierMask:mask];
    [item setTag:(NSInteger)token];
    // A role with a platform selector goes to nil, so AppKit's responder chain
    // finds whoever can do it — the focused text field, the window, NSApp.
    // Anything else is the application's own command.
    [item setTarget:action ? nil : g_commands];
    [item setEnabled:YES];
    [menu addItem:item];
    [item release];
    return CTD_OK;
}

ctd_status ctd_menu_add_separator(ctd_handle handle) {
    NSMenu *menu = ctd_menu_of(handle);
    if (!menu) return ctd_resolve(handle) ? CTD_ERR_KIND : CTD_ERR_STALE;
    [menu addItem:[NSMenuItem separatorItem]];
    return CTD_OK;
}

ctd_status ctd_menu_add_submenu(ctd_handle handle, ctd_handle child) {
    NSMenu *menu = ctd_menu_of(handle);
    NSMenu *inner = ctd_menu_of(child);
    if (!menu || !inner) return CTD_ERR_STALE;
    NSMenuItem *holder = [[NSMenuItem alloc] initWithTitle:[inner title]
                                                   action:NULL
                                            keyEquivalent:@""];
    [holder setSubmenu:inner];
    [menu addItem:holder];
    [holder release];
    return CTD_OK;
}

ctd_status ctd_menu_item_count(ctd_handle handle, int32_t *out) {
    NSMenu *menu = ctd_menu_of(handle);
    if (!menu) return ctd_resolve(handle) ? CTD_ERR_KIND : CTD_ERR_STALE;
    if (out) *out = (int32_t)[menu numberOfItems];
    return CTD_OK;
}

int32_t ctd_menu_item_title(ctd_handle handle, int32_t index, char *out, int32_t cap) {
    NSMenu *menu = ctd_menu_of(handle);
    if (!menu) return ctd_resolve(handle) ? CTD_ERR_KIND : CTD_ERR_STALE;
    if (index < 0 || index >= (int32_t)[menu numberOfItems]) return CTD_ERR_RANGE;
    NSMenuItem *item = [menu itemAtIndex:index];
    if ([item isSeparatorItem]) return ctd_copy_out(@"-", out, cap);
    return ctd_copy_out([item title], out, cap);
}

int32_t ctd_menu_item_key(ctd_handle handle, int32_t index, char *out, int32_t cap) {
    NSMenu *menu = ctd_menu_of(handle);
    if (!menu) return ctd_resolve(handle) ? CTD_ERR_KIND : CTD_ERR_STALE;
    if (index < 0 || index >= (int32_t)[menu numberOfItems]) return CTD_ERR_RANGE;
    return ctd_copy_out(ctd_shortcut_text([menu itemAtIndex:index]), out, cap);
}

// AppKit owns these application actions. Add them when a caller installs a
// normal application menu, rather than handing fake command tokens to Beans.
// This also gives a manually assembled Cortado menu the expected macOS items.
static void ctd_complete_app_menu(NSMenu *bar) {
    if ([bar numberOfItems] == 0) return;
    NSMenu *app = [[bar itemAtIndex:0] submenu];
    if (!app) return;

    NSInteger hide_index = -1;
    NSInteger quit_index = -1;
    BOOL has_native_visibility_items = NO;
    for (NSInteger index = 0; index < [app numberOfItems]; index++) {
        NSMenuItem *item = [app itemAtIndex:index];
        SEL action = [item action];
        if (action == @selector(hide:)) hide_index = index;
        if (action == @selector(terminate:)) quit_index = index;
        if (action == @selector(hideOtherApplications:) ||
            action == @selector(unhideAllApplications:) ||
            [[item title] isEqualToString:@"Services"])
            has_native_visibility_items = YES;
    }
    // A caller that supplied any of these items controls its own app menu.
    if (hide_index < 0 || quit_index <= hide_index || has_native_visibility_items) return;

    if (hide_index > 0 && ![[app itemAtIndex:hide_index - 1] isSeparatorItem]) {
        [app insertItem:[NSMenuItem separatorItem] atIndex:hide_index];
        hide_index++;
    }

    NSMenu *services = [[NSMenu alloc] initWithTitle:@"Services"];
    NSMenuItem *services_item = [[NSMenuItem alloc] initWithTitle:@"Services"
                                                        action:NULL
                                                 keyEquivalent:@""];
    [services_item setSubmenu:services];
    [app insertItem:services_item atIndex:hide_index];
    [NSApp setServicesMenu:services];
    [services_item release];
    [services release];

    // One after Services separates it from the visibility commands.
    [app insertItem:[NSMenuItem separatorItem] atIndex:hide_index + 1];
    hide_index += 2;

    NSMenuItem *others = [[NSMenuItem alloc] initWithTitle:@"Hide Others"
                                                   action:@selector(hideOtherApplications:)
                                            keyEquivalent:@"h"];
    [others setKeyEquivalentModifierMask:NSEventModifierFlagCommand |
                                         NSEventModifierFlagOption];
    [others setTarget:nil];
    [app insertItem:others atIndex:hide_index + 1];
    [others release];

    NSMenuItem *show_all = [[NSMenuItem alloc] initWithTitle:@"Show All"
                                                     action:@selector(unhideAllApplications:)
                                              keyEquivalent:@""];
    [show_all setTarget:nil];
    [app insertItem:show_all atIndex:hide_index + 2];
    [show_all release];
    [app insertItem:[NSMenuItem separatorItem] atIndex:hide_index + 3];
}

ctd_status ctd_menu_set_bar(ctd_handle handle) {
    NSMenu *menu = ctd_menu_of(handle);
    if (!menu) return ctd_resolve(handle) ? CTD_ERR_KIND : CTD_ERR_STALE;
    ctd_complete_app_menu(menu);
    [NSApp setMainMenu:menu];
    return CTD_OK;
}

// Finds an item by token anywhere under `menu`, submenus included. A token is
// the application's own number and it names one command; where that command
// was placed is not something the application should have to remember.
static NSMenuItem *ctd_find_command(NSMenu *menu, int64_t token) {
    for (NSMenuItem *item in [menu itemArray]) {
        if (!([item isSeparatorItem]) && (int64_t)[item tag] == token) return item;
        NSMenu *inner = [item submenu];
        if (inner) {
            NSMenuItem *found = ctd_find_command(inner, token);
            if (found) return found;
        }
    }
    return nil;
}

ctd_status ctd_menu_set_enabled(ctd_handle handle, int64_t token, int32_t on) {
    NSMenu *menu = ctd_menu_of(handle);
    if (!menu) return ctd_resolve(handle) ? CTD_ERR_KIND : CTD_ERR_STALE;
    NSMenuItem *item = ctd_find_command(menu, token);
    if (!item) return CTD_ERR_RANGE;
    [item setEnabled:on ? YES : NO];
    return CTD_OK;
}

ctd_status ctd_menu_set_icon(ctd_handle handle, int64_t token, int32_t icon) {
    NSMenu *menu = ctd_menu_of(handle);
    if (!menu) return ctd_resolve(handle) ? CTD_ERR_KIND : CTD_ERR_STALE;
    NSMenuItem *item = ctd_find_command(menu, token);
    if (!item) return CTD_ERR_RANGE;
    if (icon == CTD_ICON_NONE) {
        [item setImage:nil];
        return CTD_OK;
    }
    NSImage *picture = ctd_icon_image(icon);
    // Refused rather than cleared: a caller asking for an icon this system
    // cannot draw wants to know, so it can show a word instead. Silently
    // leaving the item blank is the failure this refusal exists to prevent.
    if (!picture) return CTD_ERR_RANGE;
    // It lives on the menu item, and the toolbar reads it from there — which
    // is the same reason a toolbar takes a menu at all: one description of a
    // command, in one place, and the toolbar and the menu bar both show it.
    [item setImage:picture];
    return CTD_OK;
}

ctd_status ctd_menu_invoke(ctd_handle handle, int64_t token) {
    NSMenu *menu = ctd_menu_of(handle);
    if (!menu) return ctd_resolve(handle) ? CTD_ERR_KIND : CTD_ERR_STALE;
    NSMenuItem *item = ctd_find_command(menu, token);
    if (!item) return CTD_ERR_RANGE;
    if (![item isEnabled]) return CTD_ERR_PLATFORM;
    // Through the item's own target and action, so a role's command reaches
    // the responder chain exactly as choosing it would.
    if ([item target] == g_commands) {
        [g_commands chose:item];
    } else if ([item action]) {
        [NSApp sendAction:[item action] to:[item target] from:item];
    }
    return CTD_OK;
}
