//
//  BSDisplayDDC.h
//  BlackoutSignal
//
//  Low-level Apple Silicon DDC/CI access for external displays.
//
//  All private-API / IOKit usage in this app is intentionally confined to this
//  class. It only ever touches VCP feature 0x10 (luminance / brightness). It
//  never sends power, standby, sleep or input-switch commands, because those
//  can drop the video signal and make the monitor show its "no input" screen —
//  the exact thing this app exists to avoid.
//

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

/// One online display, plus (when available) a handle to its DDC/CI channel.
@interface BSDisplayDDC : NSObject

/// CoreGraphics display id (NOT stable across reboots — use `stableKey` for persistence).
@property (nonatomic, readonly) CGDirectDisplayID displayID;

/// YES for the Mac's built-in panel (never DDC-controlled here).
@property (nonatomic, readonly) BOOL isBuiltin;

/// YES when an external DCPAVServiceProxy DDC channel was found for this display.
@property (nonatomic, readonly) BOOL supportsDDC;

@property (nonatomic, readonly) uint32_t vendor;
@property (nonatomic, readonly) uint32_t model;
@property (nonatomic, readonly) uint32_t serial;
@property (nonatomic, copy, readonly, nullable) NSString *uuid;
@property (nonatomic, copy, readonly, nullable) NSString *productName;

/// Stable identity used as a persistence key across reboots / hot-plug.
/// Prefers "vendor:model:serial", falls back to the system UUID, then the id.
@property (nonatomic, copy, readonly) NSString *stableKey;

/// Enumerate every online display and resolve its DDC channel.
+ (NSArray<BSDisplayDDC *> *)onlineDisplays;

/// Read VCP 0x10 (luminance). Returns NO on any failure (no DDC, comm error).
/// On success `current` and `max` are filled (0...max).
- (BOOL)readBrightnessCurrent:(int *)current max:(int *)max;

/// Write VCP 0x10 (luminance). Returns NO on any failure.
- (BOOL)writeBrightness:(int)value;

@end

NS_ASSUME_NONNULL_END
