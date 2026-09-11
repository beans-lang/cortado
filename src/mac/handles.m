// The handle table, and the two conversions every entry point does.
//
// A handle is an integer with a generation in it, never an address; the
// reasoning is in internal.h. Text crosses as UTF-8 with an explicit length,
// and is copied at the boundary.

#import "internal.h"

// ---------------------------------------------------------------- the table

id       g_object[CTD_SLOTS];
uint32_t g_generation[CTD_SLOTS];
int32_t  g_kind[CTD_SLOTS];
uint32_t g_used;                 // slot 0 is reserved for "no handle"

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
    // which is exactly the confusion the generation counter exists to prevent
    // everywhere else.
    ctd_clock_forget(slot);
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

// Marks a view as one cortado built.
//
// AppKit installs private subviews of its own — an NSImageView carries an
// _NSImageViewSimpleImageView — and their names and number are not API. A tree
// query that counted them would answer about AppKit's internals rather than
// about the tree the program wrote, and would change under an OS update.
static NSString *const kCortadoTag = @"cortado";

void ctd_tag(id object) {
    if ([object isKindOfClass:[NSView class]]) {
        [(NSView *)object setIdentifier:kCortadoTag];
    }
}

static BOOL ctd_is_ours(NSView *view) {
    return [[view identifier] isEqualToString:kCortadoTag];
}

// The subviews cortado put there, in order, and nothing else.
NSArray *ctd_children(NSView *container) {
    NSMutableArray *ours = [NSMutableArray array];
    for (NSView *child in [container subviews]) {
        if (ctd_is_ours(child)) [ours addObject:child];
    }
    return ours;
}

int32_t ctd_slot_kind(ctd_handle handle) {
    if (!ctd_resolve(handle)) return -1;
    return g_kind[(uint32_t)(handle & 0xffffffffu)];
}

// Copies a UTF-8 string out through the two-call shape. Answers the length the
// caller needs, writes at most `cap` bytes, and never relies on the caller
// having guessed right.
int32_t ctd_copy_out(NSString *text, char *out, int32_t cap) {
    if (!text) text = @"";
    const char *bytes = [text UTF8String];
    if (!bytes) bytes = "";
    size_t length = strlen(bytes);
    if (out && cap > 0) {
        size_t room = (size_t)cap < length ? (size_t)cap : length;
        memcpy(out, bytes, room);
    }
    return (int32_t)length;
}

// A zero byte anywhere in the text. Every entry point that takes a string
// checks, because no platform text control can hold one: NSString's
// UTF8String ends at it, GTK's const char* ends at it, and Win32's
// SetWindowTextW ends at it. Passing one through would cut a program's string
// in half somewhere inside the platform, with nothing at the boundary able to
// say where — so it is refused here, by name, while the caller's own string
// is still in view.
int ctd_has_nul(const char *utf8, int32_t len) {
    if (!utf8 || len <= 0) return 0;
    for (int32_t i = 0; i < len; i++) {
        if (utf8[i] == 0) return 1;
    }
    return 0;
}
