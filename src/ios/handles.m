// The handle table, and the two conversions every entry point does.

#import "internal.h"

//
// Identical to the macOS host's, deliberately. A handle is (generation << 32)
// | slot, so a handle used after its widget is released is a checked error
// rather than a jump into freed memory.


id       g_object[CTD_SLOTS];
uint32_t g_generation[CTD_SLOTS];
static int32_t  g_kind[CTD_SLOTS];
static int32_t  g_icon[CTD_SLOTS];  // CTD_P_ICON, per slot; see icon.*
uint32_t g_used;

ctd_event_fn g_sink;
void        *g_sink_context;
int32_t      g_role = CTD_ROLE_GUI;
int          g_started;


// Slots a released widget gave back.
//
// The handle carries a generation *so that* a slot can be reused: a stale copy
// of a handle names the old generation and answers CTD_ERR_STALE, and a new
// widget in the same slot is a different handle entirely. Without this list
// the table is an arena that only ever grows, and a program that makes and
// destroys widgets — which is every program with a list in it — runs out after
// CTD_SLOTS of them however few are alive at once.
// Named `g_recycled` rather than `g_free`: the GTK host includes glib, and
// `g_free` is one of its functions.
static uint32_t g_recycled[CTD_SLOTS];
static uint32_t g_recycled_count;

// The next slot to use: one somebody gave back, or the next never-used one.
// Zero when the table is genuinely full.
static uint32_t ctd_take_slot(void) {
    if (g_recycled_count > 0) return g_recycled[--g_recycled_count];
    if (g_used + 1 >= CTD_SLOTS) return 0;
    return ++g_used;
}

void ctd_give_back(uint32_t slot) {
    // Whatever the slot was doing stops being done. A frame clock left running
    // on a recycled slot would tick for whichever widget lands there next,
    // which is exactly the confusion the generation counter prevents
    // everywhere else.
    ctd_clock_forget(slot);
    if (g_recycled_count < CTD_SLOTS) g_recycled[g_recycled_count++] = slot;
}

// Takes a handle out of the table.
//
// The slot is cleared, its generation is bumped so that every copy of the
// handle answers CTD_ERR_STALE from here on rather than reaching whatever
// lands in the slot next, and the table gives up its own reference. Every
// release path in this host ends here, so there is one description of what
// releasing means and not one per kind of thing.
void ctd_untrack(ctd_handle handle) {
    uint32_t slot = (uint32_t)(handle & 0xffffffffu);
    if (slot == 0 || slot > g_used) return;
    if (g_generation[slot] != (uint32_t)(handle >> 32)) return;
    id object = g_object[slot];
    g_object[slot] = nil;
    g_kind[slot] = -1;
    g_icon[slot] = CTD_ICON_NONE;
    g_generation[slot] = g_generation[slot] + 1;
    if (g_generation[slot] == 0) g_generation[slot] = 1;
    ctd_give_back(slot);
    [object release];
}

ctd_handle ctd_track(id object, int32_t kind) {
    uint32_t slot = ctd_take_slot();
    if (slot == 0) return 0;
    g_object[slot] = [object retain];
    g_kind[slot] = kind;
    g_icon[slot] = CTD_ICON_NONE;
    if (g_generation[slot] == 0) g_generation[slot] = 1;
    return ((uint64_t)g_generation[slot] << 32) | slot;
}

id ctd_resolve(ctd_handle handle) {
    uint32_t slot = (uint32_t)(handle & 0xffffffffu);
    uint32_t generation = (uint32_t)(handle >> 32);
    if (slot == 0 || slot > g_used) return nil;
    if (g_generation[slot] != generation) return nil;
    return g_object[slot];
}

int32_t ctd_slot_kind(ctd_handle handle) {
    if (!ctd_resolve(handle)) return -1;
    return g_kind[(uint32_t)(handle & 0xffffffffu)];
}

// Which CTD_ICON_* a widget is showing. Kept beside the handle rather than
// read back off the control, because UIKit hands out a UIImage and there is
// no way from one to the role that asked for it.
int32_t ctd_slot_icon(ctd_handle handle) {
    if (!ctd_resolve(handle)) return CTD_ICON_NONE;
    return g_icon[(uint32_t)(handle & 0xffffffffu)];
}

void ctd_set_slot_icon(ctd_handle handle, int32_t icon) {
    if (!ctd_resolve(handle)) return;
    g_icon[(uint32_t)(handle & 0xffffffffu)] = icon;
}

// Only views cortado made are part of cortado's tree. UIKit installs private
// subviews of its own — a UITextField has several — and their names are not
// API, so counting them would make the tree depend on an iOS release.
static NSString *const kCortadoTag = @"cortado";

void ctd_tag(id object) {
    if ([object isKindOfClass:[UIView class]]) {
        [(UIView *)object setAccessibilityIdentifier:kCortadoTag];
    }
}

static BOOL ctd_is_ours(UIView *view) {
    return [[view accessibilityIdentifier] isEqualToString:kCortadoTag];
}

NSArray *ctd_children(UIView *container) {
    NSMutableArray *ours = [NSMutableArray array];
    for (UIView *child in [container subviews]) {
        if (ctd_is_ours(child)) [ours addObject:child];
    }
    return ours;
}

int32_t ctd_copy_out(NSString *text, char *out, int32_t cap) {
    if (!text) text = @"";
    const char *utf8 = [text UTF8String];
    int32_t needed = utf8 ? (int32_t)strlen(utf8) : 0;
    if (out && cap > 0) {
        int32_t n = needed < cap ? needed : cap;
        if (n > 0) memcpy(out, utf8, (size_t)n);
    }
    return needed;
}

NSString *ctd_string(const char *utf8, int32_t len) {
    NSString *text = [[[NSString alloc] initWithBytes:utf8
                                               length:(NSUInteger)(len < 0 ? 0 : len)
                                             encoding:NSUTF8StringEncoding] autorelease];
    return text ? text : @"";
}
