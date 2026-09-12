// What the operating system will let this program do, and how to ask.
//
// The rule this whole file exists to keep is in ../cortado_host.h beside
// ctd_permission_status: **never touch the framework to answer a question
// about it.** Everything below is either an Info.plist lookup or a class
// method that constructs nothing — proven safe from a bare binary with no
// bundle, across a turn of the run loop. Constructing a CBCentralManager or
// starting an AVCaptureSession is what ends the process, and nothing here
// does either.

#import "internal.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreBluetooth/CoreBluetooth.h>
#import <CoreLocation/CoreLocation.h>

// Whether this process has a privacy identity of its own.
//
// A bare binary has no bundle identifier, and TCC then answers for whatever
// process is *responsible* for it — a terminal, usually, whose grants are not
// this program's. The probe that shaped this read "microphone: authorized"
// from a program with no usage description at all.
static BOOL ctd_is_bundled(void) {
    return [[NSBundle mainBundle] bundleIdentifier] != nil;
}

// The usage-description key a permission needs, or NULL where there is none.
// Screen capture is the one with none: it is a preflight call and nothing
// else, which is why this is a function rather than a table lookup.
static NSString *ctd_permission_key(int32_t what) {
    switch (what) {
        case CTD_PERM_BLUETOOTH:  return @"NSBluetoothAlwaysUsageDescription";
        case CTD_PERM_LOCATION:   return @"NSLocationWhenInUseUsageDescription";
        case CTD_PERM_CAMERA:     return @"NSCameraUsageDescription";
        case CTD_PERM_MICROPHONE: return @"NSMicrophoneUsageDescription";
        case CTD_PERM_PHOTOS:     return @"NSPhotoLibraryUsageDescription";
        case CTD_PERM_MOTION:     return @"NSMotionUsageDescription";
        default:                  return nil;
    }
}

static int ctd_permission_is_known(int32_t what) {
    return what >= CTD_PERM_BLUETOOTH && what <= CTD_PERM_MOTION;
}

// Whether the plist says what this program wants the permission *for*. macOS
// requires the sentence before it will show a prompt, and kills a process that
// touches the framework without one.
static BOOL ctd_permission_declared(int32_t what) {
    NSString *key = ctd_permission_key(what);
    if (!key) return YES;   // screen capture asks for no sentence
    return [[NSBundle mainBundle] objectForInfoDictionaryKey:key] != nil;
}

ctd_status ctd_permission_status(int32_t what, int32_t *out) {
    if (!ctd_permission_is_known(what)) return CTD_ERR_RANGE;
    if (out) *out = CTD_ALLOW_UNAVAILABLE;
    // No bundle, no identity, no answer. See the header.
    if (!ctd_is_bundled()) return CTD_OK;
    if (!ctd_permission_declared(what)) return CTD_OK;

    int32_t answer = CTD_ALLOW_UNAVAILABLE;
    switch (what) {
        case CTD_PERM_CAMERA:
        case CTD_PERM_MICROPHONE: {
            AVMediaType media = what == CTD_PERM_CAMERA ? AVMediaTypeVideo
                                                        : AVMediaTypeAudio;
            switch ([AVCaptureDevice authorizationStatusForMediaType:media]) {
                case AVAuthorizationStatusAuthorized:    answer = CTD_ALLOW_GRANTED;   break;
                case AVAuthorizationStatusNotDetermined: answer = CTD_ALLOW_UNDECIDED; break;
                // Restricted is a denial the user cannot lift — a managed
                // device, parental controls. A caller can do nothing with the
                // difference, and a third word for it would be a third branch
                // in every program.
                default:                                 answer = CTD_ALLOW_DENIED;    break;
            }
            break;
        }
        case CTD_PERM_BLUETOOTH: {
            switch ([CBCentralManager authorization]) {
                case CBManagerAuthorizationAllowedAlways: answer = CTD_ALLOW_GRANTED;   break;
                case CBManagerAuthorizationNotDetermined: answer = CTD_ALLOW_UNDECIDED; break;
                default:                                  answer = CTD_ALLOW_DENIED;    break;
            }
            break;
        }
        case CTD_PERM_LOCATION: {
            switch ([CLLocationManager authorizationStatus]) {
                case kCLAuthorizationStatusAuthorizedAlways:
                    answer = CTD_ALLOW_GRANTED;   break;
                case kCLAuthorizationStatusNotDetermined:
                    answer = CTD_ALLOW_UNDECIDED; break;
                default:
                    answer = CTD_ALLOW_DENIED;    break;
            }
            break;
        }
        case CTD_PERM_SCREEN_CAPTURE:
            // A preflight, not a status: it answers whether the program may
            // record the screen, and asks nobody.
            answer = CGPreflightScreenCaptureAccess() ? CTD_ALLOW_GRANTED
                                                      : CTD_ALLOW_UNDECIDED;
            break;
        case CTD_PERM_PHOTOS:
        case CTD_PERM_MOTION:
            // Photos needs the Photos framework and motion needs CoreMotion,
            // which macOS does not have — see the note in the changelog. Both
            // are named here so a program can ask, and both answer that there
            // is nothing to answer.
            answer = CTD_ALLOW_UNAVAILABLE;
            break;
        default:
            answer = CTD_ALLOW_UNAVAILABLE;
            break;
    }
    if (out) *out = answer;
    return CTD_OK;
}

ctd_status ctd_permission_request(int32_t what, int64_t token) {
    if (!ctd_permission_is_known(what)) return CTD_ERR_RANGE;
    // A prompt needs a bundle to put a name on and a sentence to show. Without
    // either, asking is what kills the process — so this refuses first.
    if (!ctd_is_bundled()) return CTD_ERR_UNSUPPORTED;
    if (!ctd_permission_declared(what)) return CTD_ERR_UNSUPPORTED;

    switch (what) {
        case CTD_PERM_CAMERA:
        case CTD_PERM_MICROPHONE: {
            AVMediaType media = what == CTD_PERM_CAMERA ? AVMediaTypeVideo
                                                        : AVMediaTypeAudio;
            [AVCaptureDevice requestAccessForMediaType:media
                                     completionHandler:^(BOOL allowed) {
                // Back to the main thread: Beans is only ever entered on the
                // UI thread, and AVFoundation answers on one of its own.
                dispatch_async(dispatch_get_main_queue(), ^{
                    ctd_emit(CTD_EV_PERMISSION, 0,
                             allowed ? CTD_ALLOW_GRANTED : CTD_ALLOW_DENIED, token);
                });
            }];
            return CTD_OK;
        }
        case CTD_PERM_SCREEN_CAPTURE: {
            // CGRequestScreenCaptureAccess is synchronous and answers straight
            // away; the event still goes through the sink so a caller has one
            // shape to handle rather than two.
            BOOL allowed = CGRequestScreenCaptureAccess();
            ctd_emit(CTD_EV_PERMISSION, 0,
                     allowed ? CTD_ALLOW_GRANTED : CTD_ALLOW_DENIED, token);
            return CTD_OK;
        }
        default:
            // Bluetooth and location have no request call: the prompt appears
            // when the manager is constructed, and constructing one is the
            // thing this file exists not to do until the service that needs it
            // is written. Saying so beats prompting from a function whose name
            // says it only asks.
            return CTD_ERR_UNSUPPORTED;
    }
}
