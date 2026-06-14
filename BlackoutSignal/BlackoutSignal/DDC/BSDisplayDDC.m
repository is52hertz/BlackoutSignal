//
//  BSDisplayDDC.m
//  BlackoutSignal
//

#import "BSDisplayDDC.h"

@import IOKit;
@import CoreGraphics;

#import <unistd.h>

#pragma mark - Private IOKit / CoreDisplay symbols

// IOAVServiceRef is a private class used for I2C/DDC on Apple Silicon.
typedef CFTypeRef IOAVServiceRef;

extern IOAVServiceRef IOAVServiceCreateWithService(CFAllocatorRef allocator, io_service_t service);
extern IOReturn IOAVServiceReadI2C(IOAVServiceRef service, uint32_t chipAddress,
                                   uint32_t offset, void *outputBuffer, uint32_t outputBufferSize);
extern IOReturn IOAVServiceWriteI2C(IOAVServiceRef service, uint32_t chipAddress,
                                    uint32_t dataAddress, void *inputBuffer, uint32_t inputBufferSize);
extern CFDictionaryRef CoreDisplay_DisplayCreateInfoDictionary(CGDirectDisplayID display);

#pragma mark - DDC constants

static const uint32_t kChipAddress  = 0x37;   // 7-bit DDC/CI address
static const uint32_t kDataAddress  = 0x51;   // standard host/source data address
static const UInt8    kVCPLuminance = 0x10;   // VCP feature: brightness
static const useconds_t kDDCWait    = 10000;  // 10 ms between transactions
static const int      kDDCIterations = 2;     // write the same packet twice (display reliability)

#pragma mark - Helpers

/// Find the External DCPAVServiceProxy that lives under the given display IORegistry path,
/// mirroring the proven m1ddc approach. Returns a +1 retained IOAVServiceRef, or NULL.
static IOAVServiceRef CopyAVServiceForLocation(NSString *ioLocation) {
    if (ioLocation == nil) {
        return NULL;
    }
    io_registry_entry_t root = IORegistryGetRootEntry(kIOMainPortDefault);
    io_iterator_t iter = IO_OBJECT_NULL;
    if (IORegistryEntryCreateIterator(root, kIOServicePlane,
                                      kIORegistryIterateRecursively, &iter) != KERN_SUCCESS) {
        return NULL;
    }

    IOAVServiceRef result = NULL;
    const char *wantedPath = ioLocation.UTF8String;
    io_service_t service = IO_OBJECT_NULL;

    while ((service = IOIteratorNext(iter)) != IO_OBJECT_NULL) {
        io_string_t path = {0};
        IORegistryEntryGetPath(service, kIOServicePlane, path);
        BOOL isDisplayNode = (strcmp(path, wantedPath) == 0);
        IOObjectRelease(service);
        if (!isDisplayNode) {
            continue;
        }
        // The recursive iterator now yields this display node's descendants; the
        // DCPAVServiceProxy we want is among them.
        while ((service = IOIteratorNext(iter)) != IO_OBJECT_NULL) {
            io_name_t name = {0};
            IORegistryEntryGetName(service, name);
            if (strcmp(name, "DCPAVServiceProxy") == 0) {
                IOAVServiceRef candidate = IOAVServiceCreateWithService(kCFAllocatorDefault, service);
                CFStringRef location = (CFStringRef)IORegistryEntrySearchCFProperty(
                    service, kIOServicePlane, CFSTR("Location"),
                    kCFAllocatorDefault, kIORegistryIterateRecursively);
                BOOL external = (location != NULL &&
                                 CFGetTypeID(location) == CFStringGetTypeID() &&
                                 CFStringCompare(CFSTR("External"), location, 0) == kCFCompareEqualTo);
                if (location != NULL) {
                    CFRelease(location);
                }
                if (external && candidate != NULL) {
                    result = candidate;       // keep +1
                    IOObjectRelease(service);
                    break;
                }
                if (candidate != NULL) {
                    CFRelease(candidate);
                }
            }
            IOObjectRelease(service);
        }
        break;
    }
    IOObjectRelease(iter);
    return result;
}

#pragma mark - BSDisplayDDC

@implementation BSDisplayDDC {
    IOAVServiceRef _avService;   // +1 retained, released in -dealloc; NULL when no DDC
}

- (instancetype)initWithDisplayID:(CGDirectDisplayID)displayID {
    self = [super init];
    if (self == nil) {
        return nil;
    }
    _displayID = displayID;
    _isBuiltin = CGDisplayIsBuiltin(displayID) != 0;
    _vendor = CGDisplayVendorNumber(displayID);
    _model  = CGDisplayModelNumber(displayID);
    _serial = CGDisplaySerialNumber(displayID);

    NSString *ioLocation = nil;
    CFDictionaryRef info = CoreDisplay_DisplayCreateInfoDictionary(displayID);
    if (info != NULL) {
        CFStringRef uuid = CFDictionaryGetValue(info, CFSTR("kCGDisplayUUID"));
        if (uuid != NULL && CFGetTypeID(uuid) == CFStringGetTypeID()) {
            _uuid = [(__bridge NSString *)uuid copy];
        }
        CFStringRef loc = CFDictionaryGetValue(info, CFSTR("IODisplayLocation"));
        if (loc != NULL && CFGetTypeID(loc) == CFStringGetTypeID()) {
            ioLocation = [(__bridge NSString *)loc copy];
        }
        CFRelease(info);
    }

    // Built-in panels are never DDC-controlled (handled by the overlay only).
    if (!_isBuiltin) {
        _avService = CopyAVServiceForLocation(ioLocation);
    }
    _supportsDDC = (_avService != NULL);
    return self;
}

- (void)dealloc {
    if (_avService != NULL) {
        CFRelease(_avService);
        _avService = NULL;
    }
}

- (NSString *)stableKey {
    if (_serial != 0) {
        return [NSString stringWithFormat:@"%u:%u:%u", _vendor, _model, _serial];
    }
    if (_uuid != nil) {
        return _uuid;
    }
    if (_vendor != 0 || _model != 0) {
        return [NSString stringWithFormat:@"%u:%u:0", _vendor, _model];
    }
    return [NSString stringWithFormat:@"id:%u", _displayID];
}

+ (NSArray<BSDisplayDDC *> *)onlineDisplays {
    CGDirectDisplayID ids[16];
    uint32_t count = 0;
    if (CGGetOnlineDisplayList(16, ids, &count) != kCGErrorSuccess) {
        return @[];
    }
    NSMutableArray<BSDisplayDDC *> *displays = [NSMutableArray arrayWithCapacity:count];
    for (uint32_t i = 0; i < count; i++) {
        // Skip mirror "secondary" displays — they share the primary's framebuffer.
        if (CGDisplayMirrorsDisplay(ids[i]) != kCGNullDirectDisplay) {
            continue;
        }
        BSDisplayDDC *d = [[BSDisplayDDC alloc] initWithDisplayID:ids[i]];
        if (d != nil) {
            [displays addObject:d];
        }
    }
    return displays;
}

- (BOOL)readBrightnessCurrent:(int *)current max:(int *)max {
    if (_avService == NULL) {
        return NO;
    }
    // 1. Send the "Get VCP Feature" request for luminance.
    UInt8 request[4];
    request[0] = 0x82;
    request[1] = 0x01;
    request[2] = kVCPLuminance;
    request[3] = 0x6E ^ request[0] ^ request[1] ^ request[2];
    for (int i = 0; i < kDDCIterations; i++) {
        usleep(kDDCWait);
        if (IOAVServiceWriteI2C(_avService, kChipAddress, kDataAddress, request, sizeof(request)) != kIOReturnSuccess) {
            return NO;
        }
    }
    // 2. Read the reply: max in bytes [6..7], current in [8..9], big-endian.
    UInt8 reply[12] = {0};
    usleep(kDDCWait);
    if (IOAVServiceReadI2C(_avService, kChipAddress, kDataAddress, reply, sizeof(reply)) != kIOReturnSuccess) {
        return NO;
    }
    uint16_t mx = ((uint16_t)reply[6] << 8) | reply[7];
    uint16_t cu = ((uint16_t)reply[8] << 8) | reply[9];
    if (mx == 0 || cu > mx) {
        return NO;   // empty / nonsensical reply — treat as unreadable
    }
    if (current != NULL) {
        *current = (int)cu;
    }
    if (max != NULL) {
        *max = (int)mx;
    }
    return YES;
}

- (BOOL)writeBrightness:(int)value {
    if (_avService == NULL) {
        return NO;
    }
    if (value < 0) {
        value = 0;
    }
    UInt16 v = (UInt16)value;
    UInt8 data[6];
    data[0] = 0x84;            // length: 0x80 | (4 data bytes)
    data[1] = 0x03;            // "Set VCP Feature" opcode
    data[2] = kVCPLuminance;
    data[3] = (UInt8)(v >> 8);
    data[4] = (UInt8)(v & 0xFF);
    data[5] = 0x6E ^ kDataAddress ^ data[0] ^ data[1] ^ data[2] ^ data[3] ^ data[4];
    for (int i = 0; i < kDDCIterations; i++) {
        usleep(kDDCWait);
        if (IOAVServiceWriteI2C(_avService, kChipAddress, kDataAddress, data, sizeof(data)) != kIOReturnSuccess) {
            return NO;
        }
    }
    return YES;
}

@end
