#pragma once

#include <stdbool.h>
#include <stddef.h>

/// Loads the private multitouch framework and begins listening to the built-in trackpad.
/// Returns false when the framework or a required symbol is unavailable.
bool APStart(void);

/// Ends input delivery. Safe to call if APStart failed.
void APStop(void);

/// Enables absolute mode and filters ordinary relative pointer movement from the trackpad.
void APSetEnabled(bool enabled);

/// Enables the microscopic jitter dead-zone and output coalescing. Disable for
/// the lowest possible latency at the cost of more raw contact noise.
void APSetFiltering(bool enabled);

/// Sets global Quartz screen coordinates and the normalized active trackpad region.
void APSetMapping(double screenX, double screenY, double screenWidth, double screenHeight,
                  double areaX, double areaY, double areaWidth, double areaHeight,
                  bool invertX, bool invertY);

/// Returns the built-in trackpad's usable sensor size in millimeters when available.
bool APGetSensorDimensions(double *widthMM, double *heightMM);

/// Returns the latest one-finger contact in normalized trackpad coordinates (0...1).
/// `present` is false for no contact or a multi-finger gesture.
void APGetCurrentFinger(double *x, double *y, bool *present);

/// Writes a comma-separated list of connected HID trackpads to a caller buffer.
/// The raw absolute-input source remains the built-in Apple trackpad.
void APGetConnectedTrackpads(char *buffer, size_t bufferLength);

/// A short diagnostic string owned by the bridge; copy it immediately.
const char *APLastError(void);
