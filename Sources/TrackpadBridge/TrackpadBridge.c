#include "TrackpadBridge.h"

#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <IOKit/hid/IOHIDManager.h>
#include <dlfcn.h>
#include <math.h>
#include <stdatomic.h>
#include <stdio.h>
#include <string.h>

// These declarations are reconstructed from MultitouchSupport's ABI. The framework is
// private, so it is intentionally loaded with dlopen instead of linked at build time.
typedef void *MTDeviceRef;
typedef struct { float x, y; } MTPoint;
typedef struct { MTPoint pos, vel; } MTReadout;
typedef struct {
    int frame;
    double timestamp;
    int identifier, state, unknown1, unknown2;
    MTReadout normalized;
    float size;
    int zero;
    float angle, majorAxis, minorAxis;
    MTReadout millimeters;
    int zeros[2];
    float unknown3;
} MTFinger;
typedef int (*MTFrameCallback)(MTDeviceRef, MTFinger *, int, double, int);

typedef MTDeviceRef (*MTDeviceCreateDefaultFn)(void);
typedef CFArrayRef (*MTDeviceCreateListFn)(void);
typedef void (*MTRegisterContactFrameCallbackFn)(MTDeviceRef, MTFrameCallback);
typedef void (*MTDeviceStartFn)(MTDeviceRef, int);
typedef void (*MTDeviceStopFn)(MTDeviceRef);
typedef int (*MTDeviceGetSensorSurfaceDimensionsFn)(MTDeviceRef, int *, int *);

static void *framework = NULL;
static CFArrayRef multitouchDevices = NULL;
static MTDeviceCreateDefaultFn createDefault = NULL;
static MTDeviceCreateListFn createList = NULL;
static MTRegisterContactFrameCallbackFn registerCallback = NULL;
static MTDeviceStopFn stopDevice = NULL;
static MTDeviceStartFn startDevice = NULL;
static MTDeviceGetSensorSurfaceDimensionsFn getSensorDimensions = NULL;
static CFMachPortRef eventTap = NULL;
static CFRunLoopSourceRef eventTapSource = NULL;
static CGEventSourceRef syntheticEventSource = NULL;
static _Atomic bool enabled = false;
static _Atomic bool filteringEnabled = true;
static _Atomic double screenX = 0, screenY = 0, screenWidth = 1, screenHeight = 1;
static _Atomic double areaX = 0, areaY = 0, areaWidth = 1, areaHeight = 1;
static _Atomic bool flipX = false, flipY = true;
static _Atomic double sensorWidthMM = 0, sensorHeightMM = 0;
static _Atomic double currentFingerX = 0, currentFingerY = 0;
static _Atomic bool currentFingerPresent = false;
static MTDeviceRef activeSensorDevice = NULL;
static char lastError[256] = "Not started";

// Rejects only sub-pixel contact noise. Do not smooth: interpolation makes the
// cursor visibly chase the finger and is unacceptable for rhythm-game aiming.
static const double jitterDeadZonePoints = 0.35;
// Raw trackpad callbacks can arrive far faster than a display can present them.
// Coalescing output prevents games such as osu!lazer from building a huge SDL queue.
static const double maximumOutputRateHz = 240.0;
static bool hasFilteredTarget = false;
static CGPoint filteredTarget;
static double lastPostedAt = 0;
#define TABPAD_SYNTHETIC_EVENT_TAG 0x544142504144LL

static void setError(const char *message) {
    snprintf(lastError, sizeof(lastError), "%s", message);
}

const char *APLastError(void) { return lastError; }

static CGEventRef filterRelativeMouse(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon) {
    (void)proxy; (void)refcon;
    if (CGEventGetIntegerValueField(event, kCGEventSourceUserData) == TABPAD_SYNTHETIC_EVENT_TAG) return event;
    if (atomic_load(&enabled) && (type == kCGEventMouseMoved || type == kCGEventLeftMouseDragged || type == kCGEventRightMouseDragged)) {
        return NULL;
    }
    return event;
}

static void updateSensorDimensionsForDevice(MTDeviceRef source) {
    if (!getSensorDimensions || source == activeSensorDevice) return;
    int width = 0, height = 0;
    if (getSensorDimensions(source, &width, &height) == 0 && width > 0 && height > 0) {
        atomic_store(&sensorWidthMM, width);
        atomic_store(&sensorHeightMM, height);
        activeSensorDevice = source;
    }
}

static int frameCallback(MTDeviceRef source, MTFinger *fingers, int count, double timestamp, int frame) {
    (void)frame;
    if (count != 1 || !fingers) {
        atomic_store(&currentFingerPresent, false);
        hasFilteredTarget = false;
        return 0;
    }

    MTFinger finger = fingers[0];
    // A release frame is normally state 7. It must not cause the cursor to jump.
    if (finger.state == 7 || finger.size <= 0.0001f) {
        atomic_store(&currentFingerPresent, false);
        hasFilteredTarget = false;
        return 0;
    }

    atomic_store(&currentFingerX, finger.normalized.pos.x);
    atomic_store(&currentFingerY, finger.normalized.pos.y);
    atomic_store(&currentFingerPresent, true);
    updateSensorDimensionsForDevice(source);
    if (!atomic_load(&enabled)) return 0;

    double x = finger.normalized.pos.x;
    double y = finger.normalized.pos.y;
    double ax = atomic_load(&areaX), ay = atomic_load(&areaY);
    double aw = atomic_load(&areaWidth), ah = atomic_load(&areaHeight);
    x = (x - ax) / aw;
    y = (y - ay) / ah;
    x = fmin(1.0, fmax(0.0, x));
    y = fmin(1.0, fmax(0.0, y));
    if (atomic_load(&flipX)) x = 1.0 - x;
    if (atomic_load(&flipY)) y = 1.0 - y;
    CGPoint target = CGPointMake(atomic_load(&screenX) + x * atomic_load(&screenWidth),
                                 atomic_load(&screenY) + y * atomic_load(&screenHeight));
    if (!hasFilteredTarget) {
        filteredTarget = target;
        hasFilteredTarget = true;
        // Never delay the first point of a new contact.
        lastPostedAt = 0;
    } else if (atomic_load(&filteringEnabled)) {
        const double dx = target.x - filteredTarget.x;
        const double dy = target.y - filteredTarget.y;
        if (hypot(dx, dy) < jitterDeadZonePoints) return 0;
    }

    // MT timestamps are seconds and are monotonic for a device stream. Do the
    // inexpensive filtering on every sample, but post at most one event per 120 Hz.
    if (atomic_load(&filteringEnabled) && lastPostedAt > 0 && timestamp - lastPostedAt < 1.0 / maximumOutputRateHz) return 0;
    lastPostedAt = timestamp;
    // Preserve absolute positioning: each posted point is the real current
    // coordinate, never a smoothed point between the old and new locations.
    filteredTarget = target;

    // CGWarpMouseCursorPosition does not create events, which means osu!lazer's
    // SDL input loop never receives it. Post a tagged absolute mouse move instead.
    CGEventRef move = CGEventCreateMouseEvent(syntheticEventSource, kCGEventMouseMoved, filteredTarget, kCGMouseButtonLeft);
    if (move) {
        CGEventSetIntegerValueField(move, kCGEventSourceUserData, TABPAD_SYNTHETIC_EVENT_TAG);
        // Session posting reaches the focused application without sending the event
        // back through our HID-level physical-motion filter.
        CGEventPost(kCGSessionEventTap, move);
        CFRelease(move);
    }
    return 0;
}

bool APStart(void) {
    if (multitouchDevices) return true;
    framework = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_LAZY | RTLD_LOCAL);
    if (!framework) { setError("MultitouchSupport.framework is unavailable on this Mac."); return false; }
    createDefault = (MTDeviceCreateDefaultFn)dlsym(framework, "MTDeviceCreateDefault");
    createList = (MTDeviceCreateListFn)dlsym(framework, "MTDeviceCreateList");
    registerCallback = (MTRegisterContactFrameCallbackFn)dlsym(framework, "MTRegisterContactFrameCallback");
    startDevice = (MTDeviceStartFn)dlsym(framework, "MTDeviceStart");
    stopDevice = (MTDeviceStopFn)dlsym(framework, "MTDeviceStop");
    getSensorDimensions = (MTDeviceGetSensorSurfaceDimensionsFn)dlsym(framework, "MTDeviceGetSensorSurfaceDimensions");
    if ((!createDefault && !createList) || !registerCallback || !startDevice || !stopDevice) { setError("This macOS version has an incompatible MultitouchSupport API."); APStop(); return false; }
    // The default device is normally only the built-in trackpad. Enumerating the
    // full list also receives wireless Magic Trackpads and other Apple MT surfaces.
    multitouchDevices = createList ? createList() : NULL;
    if (!multitouchDevices || CFArrayGetCount(multitouchDevices) == 0) {
        if (multitouchDevices) { CFRelease(multitouchDevices); multitouchDevices = NULL; }
        MTDeviceRef fallback = createDefault ? createDefault() : NULL;
        if (!fallback) { setError("No Apple multitouch trackpad was found. Connect it in Bluetooth settings, then relaunch TabPad."); APStop(); return false; }
        const void *values[] = { fallback };
        multitouchDevices = CFArrayCreate(kCFAllocatorDefault, values, 1, &kCFTypeArrayCallBacks);
    }
    CFIndex deviceCount = CFArrayGetCount(multitouchDevices);
    for (CFIndex index = 0; index < deviceCount; index++) {
        MTDeviceRef source = (MTDeviceRef)CFArrayGetValueAtIndex(multitouchDevices, index);
        registerCallback(source, frameCallback);
        startDevice(source, 0);
    }
    if (getSensorDimensions && deviceCount > 0) {
        int width = 0, height = 0;
        MTDeviceRef firstDevice = (MTDeviceRef)CFArrayGetValueAtIndex(multitouchDevices, 0);
        if (getSensorDimensions(firstDevice, &width, &height) == 0 && width > 0 && height > 0) {
            atomic_store(&sensorWidthMM, width);
            atomic_store(&sensorHeightMM, height);
        }
    }

    CGEventMask mask = CGEventMaskBit(kCGEventMouseMoved) | CGEventMaskBit(kCGEventLeftMouseDragged) | CGEventMaskBit(kCGEventRightMouseDragged);
    eventTap = CGEventTapCreate(kCGHIDEventTap, kCGHeadInsertEventTap, 0, mask, filterRelativeMouse, NULL);
    if (!eventTap) { setError("Could not install the pointer filter. Grant Accessibility permission, then relaunch."); APStop(); return false; }
    eventTapSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0);
    CFRunLoopAddSource(CFRunLoopGetMain(), eventTapSource, kCFRunLoopCommonModes);
    CGEventTapEnable(eventTap, true);
    syntheticEventSource = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
    if (!syntheticEventSource) { setError("Could not create a synthetic pointer event source."); APStop(); return false; }
    setError("Ready");
    return true;
}

void APStop(void) {
    atomic_store(&enabled, false);
    hasFilteredTarget = false;
    lastPostedAt = 0;
    activeSensorDevice = NULL;
    if (eventTapSource) { CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapSource, kCFRunLoopCommonModes); CFRelease(eventTapSource); eventTapSource = NULL; }
    if (eventTap) { CFMachPortInvalidate(eventTap); CFRelease(eventTap); eventTap = NULL; }
    if (syntheticEventSource) { CFRelease(syntheticEventSource); syntheticEventSource = NULL; }
    if (multitouchDevices && stopDevice) {
        CFIndex deviceCount = CFArrayGetCount(multitouchDevices);
        for (CFIndex index = 0; index < deviceCount; index++) {
            stopDevice((MTDeviceRef)CFArrayGetValueAtIndex(multitouchDevices, index));
        }
        CFRelease(multitouchDevices);
        multitouchDevices = NULL;
    }
    if (framework) { dlclose(framework); framework = NULL; }
}

void APSetEnabled(bool value) { atomic_store(&enabled, value); }

void APSetFiltering(bool value) {
    atomic_store(&filteringEnabled, value);
    // Make the next point immediate after a mode change.
    hasFilteredTarget = false;
    lastPostedAt = 0;
}

void APSetMapping(double sx, double sy, double sw, double sh, double ax, double ay, double aw, double ah, bool invertX, bool invertY) {
    atomic_store(&screenX, sx); atomic_store(&screenY, sy); atomic_store(&screenWidth, fmax(sw, 1)); atomic_store(&screenHeight, fmax(sh, 1));
    atomic_store(&areaX, fmin(1, fmax(0, ax))); atomic_store(&areaY, fmin(1, fmax(0, ay)));
    atomic_store(&areaWidth, fmin(1, fmax(0.0001, aw))); atomic_store(&areaHeight, fmin(1, fmax(0.0001, ah)));
    atomic_store(&flipX, invertX); atomic_store(&flipY, invertY);
}

bool APGetSensorDimensions(double *widthMM, double *heightMM) {
    double width = atomic_load(&sensorWidthMM), height = atomic_load(&sensorHeightMM);
    if (widthMM) *widthMM = width;
    if (heightMM) *heightMM = height;
    return width > 0 && height > 0;
}

void APGetCurrentFinger(double *x, double *y, bool *present) {
    if (x) *x = atomic_load(&currentFingerX);
    if (y) *y = atomic_load(&currentFingerY);
    if (present) *present = atomic_load(&currentFingerPresent);
}

void APGetConnectedTrackpads(char *buffer, size_t bufferLength) {
    if (!buffer || bufferLength == 0) return;
    snprintf(buffer, bufferLength, "Built-in trackpad");

    IOHIDManagerRef manager = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    if (!manager) return;
    const int usagePage = kHIDPage_Digitizer;
    const int usage = kHIDUsage_Dig_TouchPad;
    CFNumberRef page = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &usagePage);
    CFNumberRef use = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &usage);
    const void *keys[] = { CFSTR(kIOHIDDeviceUsagePageKey), CFSTR(kIOHIDDeviceUsageKey) };
    const void *values[] = { page, use };
    CFDictionaryRef match = CFDictionaryCreate(kCFAllocatorDefault, keys, values, 2, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    IOHIDManagerSetDeviceMatching(manager, match);
    IOHIDManagerOpen(manager, kIOHIDOptionsTypeNone);
    CFSetRef devices = IOHIDManagerCopyDevices(manager);
    if (devices && CFSetGetCount(devices) > 0) {
        CFIndex count = CFSetGetCount(devices);
        const void **items = calloc((size_t)count, sizeof(void *));
        if (items) {
            CFSetGetValues(devices, items);
            buffer[0] = '\0';
            for (CFIndex index = 0; index < count; index++) {
                IOHIDDeviceRef hid = (IOHIDDeviceRef)items[index];
                CFStringRef product = IOHIDDeviceGetProperty(hid, CFSTR(kIOHIDProductKey));
                CFStringRef transport = IOHIDDeviceGetProperty(hid, CFSTR(kIOHIDTransportKey));
                char productText[160] = "Unknown trackpad";
                char transportText[48] = "";
                if (product) CFStringGetCString(product, productText, sizeof(productText), kCFStringEncodingUTF8);
                if (transport) CFStringGetCString(transport, transportText, sizeof(transportText), kCFStringEncodingUTF8);
                size_t used = strlen(buffer);
                snprintf(buffer + used, bufferLength > used ? bufferLength - used : 0, "%s%s%s%s",
                         used ? ", " : "", productText, transportText[0] ? " (" : "", transportText[0] ? transportText : "");
                if (transportText[0]) {
                    used = strlen(buffer);
                    snprintf(buffer + used, bufferLength > used ? bufferLength - used : 0, ")");
                }
            }
            free(items);
        }
    }
    if (devices) CFRelease(devices);
    IOHIDManagerClose(manager, kIOHIDOptionsTypeNone);
    CFRelease(manager);
    CFRelease(match);
    CFRelease(page);
    CFRelease(use);
}
