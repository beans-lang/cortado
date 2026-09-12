// Where the machine is, what is nearby, what it can see and hear, and what is
// on its screen.
//
// **Every function in this file can end the process, and one guard stops all
// of them.** `ctd_gated` is in permission.m and is called first in every entry
// point here, without exception — a bundle, a declared reason, and a
// permission that is not already denied, all read without touching a
// framework. Anything that fails it answers CTD_ERR_UNSUPPORTED and touches
// nothing.
//
// The rule is worth stating once more because the failure it prevents is not
// an error: macOS does not refuse a program that reaches a gated framework
// without a usage description, it **terminates** it, on a later turn of the
// run loop, in unrelated code, with nothing on stderr. A service that forgot
// the guard would not fail its own test — it would take the suite down
// somewhere else, and the stack would be about whatever was running then.
//
// Which is why `tests/gated.b` runs on the ordinary legs and checks exactly
// one thing: that every one of these refuses, from a process with no bundle,
// and that the program is still alive to say so.

#import "internal.h"

#import <AVFoundation/AVFoundation.h>
#import <CoreBluetooth/CoreBluetooth.h>
#import <CoreLocation/CoreLocation.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>

// ------------------------------------------------------- where the machine is

@interface CortadoPlace : NSObject <CLLocationManagerDelegate>
@end

static CLLocationManager *g_place;
static CortadoPlace      *g_place_delegate;
static double             g_fix[4];
static int                g_have_fix;

@implementation CortadoPlace
- (void)locationManager:(CLLocationManager *)manager
     didUpdateLocations:(NSArray<CLLocation *> *)places {
    (void)manager;
    CLLocation *now = [places lastObject];
    if (!now) return;
    g_fix[0] = [now coordinate].latitude;
    g_fix[1] = [now coordinate].longitude;
    g_fix[2] = [now horizontalAccuracy];
    // A course is where it is *going*, which is only known while moving; -1 is
    // CoreLocation's own word for "not known" and is passed straight through
    // rather than turned into a heading of due north.
    g_fix[3] = [now course];
    g_have_fix = 1;
    if (!g_sink || !ctd_listening(CTD_EV_LOCATION)) return;
    ctd_event out;
    memset(&out, 0, sizeof out);
    out.kind = CTD_EV_LOCATION;
    out.x = g_fix[0];
    out.y = g_fix[1];
    out.width = g_fix[2];
    out.height = g_fix[3];
    g_sink(g_sink_context, &out);
}
- (void)locationManager:(CLLocationManager *)manager
       didFailWithError:(NSError *)problem {
    (void)manager; (void)problem;
    // Deliberately silent. CoreLocation fails for as long as it has no fix —
    // indoors, that is every second — and a program told about each would hear
    // nothing but failure while it waited for the answer it asked for.
}
@end

ctd_status ctd_location_start(void) {
    ctd_status allowed = ctd_gated(CTD_PERM_LOCATION);
    if (allowed != CTD_OK) return allowed;
    if (!g_place) {
        g_place_delegate = [[CortadoPlace alloc] init];
        g_place = [[CLLocationManager alloc] init];
        [g_place setDelegate:g_place_delegate];
        // Requesting is what makes the prompt appear, and it is safe here and
        // only here: the guard above has already read the plist.
        [g_place requestWhenInUseAuthorization];
    }
    [g_place startUpdatingLocation];
    return CTD_OK;
}

ctd_status ctd_location_stop(void) {
    if (!g_place) return CTD_OK;
    [g_place stopUpdatingLocation];
    return CTD_OK;
}

ctd_status ctd_location_last(double *out) {
    ctd_status allowed = ctd_gated(CTD_PERM_LOCATION);
    if (allowed != CTD_OK) return allowed;
    // Four zeroes are a real place in the Gulf of Guinea, so a fix that has
    // not arrived is a state and not a reading.
    if (!g_have_fix) return CTD_ERR_STATE;
    if (out) memcpy(out, g_fix, sizeof g_fix);
    return CTD_OK;
}

// ---------------------------------------------------------- what is nearby

@interface CortadoRadio : NSObject <CBCentralManagerDelegate>
@end

static CBCentralManager *g_radio;
static CortadoRadio     *g_radio_delegate;
// The rows, in the order they were first seen. A row keeps its number for as
// long as the scan does, which is what lets an event name one with an integer
// instead of a string — and what the header promises.
static NSMutableArray<CBPeripheral *> *g_seen;
static NSMutableArray<NSNumber *>     *g_signal;

static int32_t ctd_row_of(CBPeripheral *found) {
    for (NSUInteger i = 0; i < [g_seen count]; i++) {
        if ([g_seen objectAtIndex:i] == found) return (int32_t)i;
    }
    return -1;
}

@implementation CortadoRadio
- (void)centralManagerDidUpdateState:(CBCentralManager *)central {
    (void)central;
    // Required by the protocol. The state is read where it is needed rather
    // than kept here, because it changes and a copy would go stale.
}
- (void)centralManager:(CBCentralManager *)central
 didDiscoverPeripheral:(CBPeripheral *)found
     advertisementData:(NSDictionary<NSString *, id> *)advert
                  RSSI:(NSNumber *)signal {
    (void)central; (void)advert;
    int32_t row = ctd_row_of(found);
    if (row < 0) {
        [g_seen addObject:found];
        [g_signal addObject:signal];
        row = (int32_t)[g_seen count] - 1;
    } else {
        [g_signal replaceObjectAtIndex:(NSUInteger)row withObject:signal];
    }
    if (!g_sink || !ctd_listening(CTD_EV_BLE_FOUND)) return;
    ctd_event out;
    memset(&out, 0, sizeof out);
    out.kind = CTD_EV_BLE_FOUND;
    out.index = row;
    out.x = [signal doubleValue];
    g_sink(g_sink_context, &out);
}
- (void)ctdLink:(CBPeripheral *)which up:(int)up {
    int32_t row = ctd_row_of(which);
    if (row < 0 || !g_sink || !ctd_listening(CTD_EV_BLE_LINK)) return;
    ctd_event out;
    memset(&out, 0, sizeof out);
    out.kind = CTD_EV_BLE_LINK;
    out.index = row;
    out.token = up;
    g_sink(g_sink_context, &out);
}
- (void)centralManager:(CBCentralManager *)central
  didConnectPeripheral:(CBPeripheral *)which {
    (void)central;
    [self ctdLink:which up:1];
}
- (void)centralManager:(CBCentralManager *)central
didDisconnectPeripheral:(CBPeripheral *)which
                 error:(NSError *)problem {
    (void)central; (void)problem;
    [self ctdLink:which up:0];
}
- (void)centralManager:(CBCentralManager *)central
didFailToConnectPeripheral:(CBPeripheral *)which
                 error:(NSError *)problem {
    (void)central; (void)problem;
    // A failed connection is a connection that is not up, which is what a
    // program acts on. Two words for it would be two branches in every one.
    [self ctdLink:which up:0];
}
@end

static ctd_status ctd_radio_ready(void) {
    ctd_status allowed = ctd_gated(CTD_PERM_BLUETOOTH);
    if (allowed != CTD_OK) return allowed;
    if (g_radio) return CTD_OK;
    g_seen = [[NSMutableArray alloc] init];
    g_signal = [[NSMutableArray alloc] init];
    g_radio_delegate = [[CortadoRadio alloc] init];
    // Constructing this is what prompts, and it is safe here and only here:
    // the guard above has already read the plist.
    g_radio = [[CBCentralManager alloc] initWithDelegate:g_radio_delegate queue:nil];
    return CTD_OK;
}

ctd_status ctd_ble_scan(int32_t on) {
    ctd_status ready = ctd_radio_ready();
    if (ready != CTD_OK) return ready;
    if (!on) { [g_radio stopScan]; return CTD_OK; }
    // The radio takes a moment to come up and a scan started before it has is
    // ignored by CoreBluetooth without saying so. Saying so is better.
    if ([g_radio state] != CBManagerStatePoweredOn) return CTD_ERR_STATE;
    [g_radio scanForPeripheralsWithServices:nil options:nil];
    return CTD_OK;
}

int32_t ctd_ble_count(void) {
    if (ctd_gated(CTD_PERM_BLUETOOTH) != CTD_OK) return 0;
    return (int32_t)[g_seen count];
}

static CBPeripheral *ctd_ble_at(int32_t row) {
    if (ctd_gated(CTD_PERM_BLUETOOTH) != CTD_OK) return nil;
    if (row < 0 || (NSUInteger)row >= [g_seen count]) return nil;
    return [g_seen objectAtIndex:(NSUInteger)row];
}

int32_t ctd_ble_name(int32_t row, char *out, int32_t cap) {
    CBPeripheral *which = ctd_ble_at(row);
    if (!which) return CTD_ERR_RANGE;
    // Often empty, and that is the device's choice rather than a failure: a
    // peripheral is not obliged to advertise a name and most do not until they
    // are connected.
    NSString *called = [which name];
    return ctd_copy_out(called ? called : @"", out, cap);
}

int32_t ctd_ble_id(int32_t row, char *out, int32_t cap) {
    CBPeripheral *which = ctd_ble_at(row);
    if (!which) return CTD_ERR_RANGE;
    // Not the hardware address — Apple does not hand that out. It is stable
    // for this machine and this device, which is what a program storing it
    // actually needs.
    return ctd_copy_out([[which identifier] UUIDString], out, cap);
}

ctd_status ctd_ble_signal(int32_t row, double *out) {
    if (ctd_gated(CTD_PERM_BLUETOOTH) != CTD_OK) return CTD_ERR_UNSUPPORTED;
    if (row < 0 || (NSUInteger)row >= [g_signal count]) return CTD_ERR_RANGE;
    if (out) *out = [[g_signal objectAtIndex:(NSUInteger)row] doubleValue];
    return CTD_OK;
}

ctd_status ctd_ble_connect(int32_t row, int32_t on) {
    CBPeripheral *which = ctd_ble_at(row);
    if (!which) return CTD_ERR_RANGE;
    if (on) [g_radio connectPeripheral:which options:nil];
    else    [g_radio cancelPeripheralConnection:which];
    return CTD_OK;
}

int32_t ctd_ble_linked(int32_t row) {
    CBPeripheral *which = ctd_ble_at(row);
    if (!which) return 0;
    return [which state] == CBPeripheralStateConnected ? 1 : 0;
}

// -------------------------------------------- what it can see and hear

static AVMediaType ctd_media_of(int32_t kind) {
    return kind == CTD_CAPTURE_MICROPHONE ? AVMediaTypeAudio : AVMediaTypeVideo;
}

static int32_t ctd_capture_permission(int32_t kind) {
    return kind == CTD_CAPTURE_MICROPHONE ? CTD_PERM_MICROPHONE : CTD_PERM_CAMERA;
}

// The devices of a kind, asked fresh each time.
//
// A cached list is a list that is wrong the moment somebody unplugs a webcam,
// and AVFoundation's own discovery session is cheap. What cortado promises is
// that a row keeps its number until CTD_EV_CAPTURE_DEVICES says otherwise, and
// the order is the platform's own, which does not change under a program.
static NSArray<AVCaptureDevice *> *ctd_capture_devices(int32_t kind) {
    if (kind != CTD_CAPTURE_CAMERA && kind != CTD_CAPTURE_MICROPHONE) return nil;
    if (ctd_gated(ctd_capture_permission(kind)) != CTD_OK) return nil;
    NSArray<AVCaptureDeviceType> *types = kind == CTD_CAPTURE_MICROPHONE
        ? @[AVCaptureDeviceTypeMicrophone]
        : @[AVCaptureDeviceTypeBuiltInWideAngleCamera, AVCaptureDeviceTypeExternal];
    AVCaptureDeviceDiscoverySession *found =
        [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:types
                                                               mediaType:ctd_media_of(kind)
                                                                position:AVCaptureDevicePositionUnspecified];
    return [found devices];
}

int32_t ctd_capture_count(int32_t kind) {
    NSArray *devices = ctd_capture_devices(kind);
    return devices ? (int32_t)[devices count] : 0;
}

int32_t ctd_capture_name(int32_t kind, int32_t row, char *out, int32_t cap) {
    NSArray<AVCaptureDevice *> *devices = ctd_capture_devices(kind);
    if (!devices) return CTD_ERR_UNSUPPORTED;
    if (row < 0 || (NSUInteger)row >= [devices count]) return CTD_ERR_RANGE;
    return ctd_copy_out([[devices objectAtIndex:(NSUInteger)row] localizedName], out, cap);
}

int32_t ctd_capture_is_default(int32_t kind, int32_t row) {
    NSArray<AVCaptureDevice *> *devices = ctd_capture_devices(kind);
    if (!devices || row < 0 || (NSUInteger)row >= [devices count]) return 0;
    AVCaptureDevice *standard = [AVCaptureDevice defaultDeviceWithMediaType:ctd_media_of(kind)];
    return standard && [devices objectAtIndex:(NSUInteger)row] == standard ? 1 : 0;
}

// ------------------------------------------------- what is on the screen

int32_t ctd_screen_count(void) {
    if (ctd_gated(CTD_PERM_SCREEN_CAPTURE) != CTD_OK) return 0;
    return (int32_t)[[NSScreen screens] count];
}

ctd_status ctd_screen_size(int32_t display, double *out) {
    ctd_status allowed = ctd_gated(CTD_PERM_SCREEN_CAPTURE);
    if (allowed != CTD_OK) return allowed;
    NSArray<NSScreen *> *screens = [NSScreen screens];
    if (display < 0 || (NSUInteger)display >= [screens count]) return CTD_ERR_RANGE;
    NSScreen *one = [screens objectAtIndex:(NSUInteger)display];
    NSRect frame = [one frame];
    // Pixels rather than points, because that is what a frame of it will be.
    double scale = [one backingScaleFactor];
    if (out) {
        out[0] = frame.size.width * scale;
        out[1] = frame.size.height * scale;
    }
    return CTD_OK;
}

// One frame of a display, asked for and delivered.
//
// **`CGDisplayCreateImage` is gone.** macOS 15 marks it unavailable rather
// than deprecated — the symbol does not compile — and ScreenCaptureKit is what
// replaced it. A frame arrives on a queue, so the call that asks cannot be the
// call that answers, and the token-keyed shape the rest of this ABI uses for
// anything slow is what this became.
static NSMutableDictionary<NSNumber *, NSData *> *g_frames;
static NSMutableDictionary<NSNumber *, NSValue *> *g_frame_sizes;

static void ctd_screen_ready(int64_t token, NSData *pixels, CGSize size) {
    if (pixels) {
        if (!g_frames) {
            g_frames = [[NSMutableDictionary alloc] init];
            g_frame_sizes = [[NSMutableDictionary alloc] init];
        }
        [g_frames setObject:pixels forKey:[NSNumber numberWithLongLong:token]];
        [g_frame_sizes setObject:[NSValue valueWithSize:NSMakeSize(size.width, size.height)]
                          forKey:[NSNumber numberWithLongLong:token]];
    }
    if (!g_sink || !ctd_listening(CTD_EV_SCREEN_FRAME)) return;
    ctd_event out;
    memset(&out, 0, sizeof out);
    out.kind = CTD_EV_SCREEN_FRAME;
    out.token = token;
    out.index = pixels ? (int64_t)[pixels length] : 0;
    g_sink(g_sink_context, &out);
}

// A CGImage's rows are padded to whatever stride Core Graphics chose, so the
// bytes cannot be handed out as they are: a caller reading width*4 per row
// would smear. Redrawn into a tight buffer, which is also what makes the
// answer the same 8-bit RGBA `ctd_snapshot` gives.
static NSData *ctd_tight_rgba(CGImageRef shot) {
    size_t width = CGImageGetWidth(shot);
    size_t height = CGImageGetHeight(shot);
    if (width == 0 || height == 0) return nil;
    NSMutableData *pixels = [NSMutableData dataWithLength:width * height * 4];
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef paper = CGBitmapContextCreate([pixels mutableBytes], width, height,
                                               8, width * 4, space,
                                               kCGImageAlphaPremultipliedLast |
                                               kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (!paper) return nil;
    CGContextDrawImage(paper, CGRectMake(0, 0, (CGFloat)width, (CGFloat)height), shot);
    CGContextRelease(paper);
    return pixels;
}

ctd_status ctd_screen_capture(int32_t display, int64_t token) {
    ctd_status allowed = ctd_gated(CTD_PERM_SCREEN_CAPTURE);
    if (allowed != CTD_OK) return allowed;
    NSArray<NSScreen *> *screens = [NSScreen screens];
    if (display < 0 || (NSUInteger)display >= [screens count]) return CTD_ERR_RANGE;
    CGDirectDisplayID which = (CGDirectDisplayID)[[[[screens objectAtIndex:(NSUInteger)display]
        deviceDescription] objectForKey:@"NSScreenNumber"] unsignedIntValue];

    // SCShareableContent is itself asynchronous, so this is two hops: what is
    // on the screen, and then a picture of it.
    [SCShareableContent getShareableContentWithCompletionHandler:
        ^(SCShareableContent *content, NSError *problem) {
        SCDisplay *found = nil;
        if (!problem) {
            for (SCDisplay *one in [content displays]) {
                if ([one displayID] == which) { found = one; break; }
            }
        }
        if (!found) {
            dispatch_async(dispatch_get_main_queue(), ^{
                ctd_screen_ready(token, nil, CGSizeZero);
            });
            return;
        }
        SCContentFilter *only = [[SCContentFilter alloc] initWithDisplay:found
                                                       excludingWindows:@[]];
        SCStreamConfiguration *how = [[SCStreamConfiguration alloc] init];
        [how setWidth:(size_t)[found width]];
        [how setHeight:(size_t)[found height]];
        [SCScreenshotManager captureImageWithFilter:only configuration:how
                                  completionHandler:^(CGImageRef shot, NSError *failed) {
            NSData *pixels = (shot && !failed) ? ctd_tight_rgba(shot) : nil;
            CGSize size = shot ? CGSizeMake((CGFloat)CGImageGetWidth(shot),
                                            (CGFloat)CGImageGetHeight(shot))
                               : CGSizeZero;
            // Onto the UI thread before Beans is entered, like every other
            // answer that arrives on somebody else's queue.
            dispatch_async(dispatch_get_main_queue(), ^{
                ctd_screen_ready(token, pixels, size);
            });
        }];
        [only release];
        [how release];
    }];
    return CTD_OK;
}

int32_t ctd_screen_take(int64_t token, double *out_size,
                        uint8_t *out, int32_t cap) {
    if (ctd_gated(CTD_PERM_SCREEN_CAPTURE) != CTD_OK) return CTD_ERR_UNSUPPORTED;
    NSNumber *key = [NSNumber numberWithLongLong:token];
    NSData *pixels = [g_frames objectForKey:key];
    if (!pixels) return CTD_ERR_STATE;
    NSValue *boxed = [g_frame_sizes objectForKey:key];
    NSSize size = boxed ? [boxed sizeValue] : NSMakeSize(0, 0);
    if (out_size) { out_size[0] = size.width; out_size[1] = size.height; }
    int32_t length = (int32_t)[pixels length];
    if (!out || cap <= 0) return length;
    if (cap < length) return CTD_ERR_RANGE;
    memcpy(out, [pixels bytes], (size_t)length);
    // Forgotten once read. A Retina display is thirty megabytes a frame and
    // holding the last one for a caller that may never ask again would be
    // thirty megabytes this library keeps for nothing.
    [g_frames removeObjectForKey:key];
    [g_frame_sizes removeObjectForKey:key];
    return length;
}
