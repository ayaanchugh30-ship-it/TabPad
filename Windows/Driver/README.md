# Windows driver component

The future driver is a KMDF package with two responsibilities:

1. Filter the selected physical Precision Touchpad’s HID reports without binding to unrelated HID devices.
2. Create a VHF-backed virtual absolute-pointer device for games that require ordinary HID input.

It must include:

- Strict hardware-ID matching in the INF
- Device-specific report-descriptor parsing
- An authenticated user-mode control channel
- A failsafe disable/uninstall path that restores ordinary touchpad operation
- Driver signing for release builds

This folder intentionally contains no installable driver until a specific Windows touchpad descriptor is validated.
