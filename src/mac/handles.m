// The handle table, and the two conversions every entry point does.
//
// A handle is an integer with a generation in it, never an address; the
// reasoning is in internal.h. Text crosses as UTF-8 with an explicit length,
// and is copied at the boundary.

#import "internal.h"

// The other direction: the handle for an object cortado is holding.
//
// Input needs it and nothing else does. An event arrives naming a *view* —
// AppKit hit-tests, GTK hands the controller its widget — and cortado has to
// answer with the handle a program knows the control by. A scan of the slot
// table would answer correctly and would run once per mouse move, which on a
// pointer that reports a thousand times a second is a thousand scans of every
// control in the window. So the reverse is kept as it is built.
//
// Opaque personality on both sides: the keys are compared by pointer, never by
// -isEqual:, because two NSButtons with the same title are two controls. Weak
// keys, so an object that goes releases its row without ctd_untrack having to
// find it.
static NSMapTable *g_reverse = nil;

static NSMapTable *ctd_reverse_table(void) {
    if (!g_reverse) {
        g_reverse = [[NSMapTable alloc]
            initWithKeyOptions:(NSPointerFunctionsWeakMemory |
                                NSPointerFunctionsOpaquePersonality)
                  valueOptions:(NSPointerFunctionsOpaqueMemory |
                                NSPointerFunctionsIntegerPersonality)
                      capacity:64];
    }
    return g_reverse;
}


// ---------------------------------------------------------------- the table

id       g_object[CTD_SLOTS];
uint32_t g_generation[CTD_SLOTS];
int32_t  g_kind[CTD_SLOTS];
int32_t  g_icon[CTD_SLOTS];  // CTD_P_ICON, per slot; see icon.*
uint32_t g_used;                 // slot 0 is reserved for "no handle"

ctd_event_fn g_sink;
// See internal.h: non-zero while cortado writes on the program's behalf.
int g_writing = 0;
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
    // Out of the reverse table before the slot is cleared. The keys are weak,
    // so a released object would drop its own row — but a *recycled* slot
    // would not, and a stale row would answer an old handle for a live view.
    if (object) NSMapRemove(ctd_reverse_table(), (const void *)object);
    g_object[slot] = nil;
    g_kind[slot] = -1;
    g_icon[slot] = CTD_ICON_NONE;
    g_generation[slot]++;
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
    ctd_handle handle = ((uint64_t)g_generation[slot] << 32) | slot;
    NSMapInsert(ctd_reverse_table(), (const void *)object,
                (void *)(uintptr_t)handle);
    return handle;
}

ctd_handle ctd_handle_for(id object) {
    if (!object) return 0;
    void *kept = NSMapGet(ctd_reverse_table(), (const void *)object);
    return (ctd_handle)(uintptr_t)kept;
}

// The nearest ancestor cortado knows, starting with the view itself.
//
// AppKit builds private subviews of its own — a click inside an NSButton can
// hit-test to a cell's backing view whose class is not API — so the view an
// event names is not always one cortado made. Walking up stops at the first
// one it did, which is the control a person would say was clicked.
ctd_handle ctd_handle_for_view(NSView *view) {
    while (view) {
        ctd_handle found = ctd_handle_for(view);
        if (found) return found;
        view = [view superview];
    }
    return 0;
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
