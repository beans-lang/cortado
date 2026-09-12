// What the operating system will let this program do, and how to ask.
//
// The same rule as the macOS host, and the same reason: never touch the
// framework to answer a question about it. What differs is the inventory. A
// phone has no screen-capture grant of this kind, and the two frameworks macOS
// lacks — Photos and CoreMotion — are here, but the services behind them are
// not written yet, so both answer that there is nothing to answer rather than
// a number nothing can act on.

#import "internal.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreBluetooth/CoreBluetooth.h>
#import <CoreLocation/CoreLocation.h>

static BOOL ctd_is_bundled(void) {
    return [[NSBundle mainBundle] bundleIdentifier] != nil;
}

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

static BOOL ctd_permission_declared(int32_t what) {
    NSString *key = ctd_permission_key(what);
    if (!key) return NO;
    return [[NSBundle mainBundle] objectForInfoDictionaryKey:key] != nil;
}

ctd_status ctd_permission_status(int32_t what, int32_t *out) {
    if (!ctd_permission_is_known(what)) return CTD_ERR_RANGE;
    if (out) *out = CTD_ALLOW_UNAVAILABLE;
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
            // Deprecated since macOS 11 and iOS 14 in favour of an *instance*
            // property — which needs a CLLocationManager, and constructing one
            // is the thing this file exists not to do. The class method is the
            // only way to read the status without touching the framework, so
            // the warning is turned off here rather than the call being
            // changed: a build full of noise is a build whose real warnings
            // nobody reads.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            switch ([CLLocationManager authorizationStatus]) {
                case kCLAuthorizationStatusAuthorizedAlways:
                case kCLAuthorizationStatusAuthorizedWhenInUse:
                    answer = CTD_ALLOW_GRANTED;   break;
                case kCLAuthorizationStatusNotDetermined:
                    answer = CTD_ALLOW_UNDECIDED; break;
                default:
                    answer = CTD_ALLOW_DENIED;    break;
            }
#pragma clang diagnostic pop
            break;
        }
        default:
            // Screen capture is not a grant a phone has; Photos and motion are
            // frameworks whose services cortado has not written, and a status
            // for a service nothing can use is a number nobody can act on.
            answer = CTD_ALLOW_UNAVAILABLE;
            break;
    }
    if (out) *out = answer;
    return CTD_OK;
}

ctd_status ctd_permission_request(int32_t what, int64_t token) {
    if (!ctd_permission_is_known(what)) return CTD_ERR_RANGE;
    if (!ctd_is_bundled()) return CTD_ERR_UNSUPPORTED;
    if (!ctd_permission_declared(what)) return CTD_ERR_UNSUPPORTED;
    switch (what) {
        case CTD_PERM_CAMERA:
        case CTD_PERM_MICROPHONE: {
            AVMediaType media = what == CTD_PERM_CAMERA ? AVMediaTypeVideo
                                                        : AVMediaTypeAudio;
            [AVCaptureDevice requestAccessForMediaType:media
                                     completionHandler:^(BOOL allowed) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    ctd_emit(CTD_EV_PERMISSION, 0,
                             allowed ? CTD_ALLOW_GRANTED : CTD_ALLOW_DENIED, token);
                });
            }];
            return CTD_OK;
        }
        default:
            return CTD_ERR_UNSUPPORTED;
    }
}
