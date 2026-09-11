// The handle table, and the two conversions every entry point does.

#import "internal.h"

//
// Identical to the macOS host's, deliberately. A handle is (generation << 32)
// | slot, so a handle used after its widget is released is a checked error
// rather than a jump into freed memory.


id       g_object[CTD_SLOTS];
uint32_t g_generation[CTD_SLOTS];
static int32_t  g_kind[CTD_SLOTS];
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
    if (g_recycled_count < CTD_SLOTS) g_recycled[g_recycled_count++] = slot;
}

ctd_handle ctd_track(id object, int32_t kind) {
    uint32_t slot = ctd_take_slot();
    if (slot == 0) return 0;
    g_object[slot] = [object retain];
    g_kind[slot] = kind;
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
