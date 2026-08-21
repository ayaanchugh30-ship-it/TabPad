# TabPad for Windows

## Status

This folder is the Windows implementation workstream. It is **not yet a working Windows app or driver**.

TabPad’s macOS build can read raw trackpad contacts through an Apple-private framework. A generic Windows equivalent needs a different, privileged architecture: a signed HID filter driver to read the selected physical touchpad and a Virtual HID Framework (VHF) driver to expose mapped input to games.

Do not treat a normal user-mode Windows app that moves the cursor relatively as an equivalent; it cannot obtain global, one-finger absolute coordinates from a Precision Touchpad.

## Why a driver is required

Windows Precision Touchpads report contact X/Y data as a Digitizer/Touch Pad HID collection. Windows normally consumes those reports and turns them into ordinary pointer and gesture input. Applications do not receive global one-finger touchpad contacts by default.

To implement TabPad on Windows, the project needs:

1. A lower HID filter bound only to the user-selected touchpad.
2. A device-specific HID report parser that extracts one-finger absolute coordinates.
3. A user-mode configuration app that receives filtered coordinates through a secure IOCTL interface.
4. A VHF-backed virtual absolute mouse/tablet device that receives mapped, filtered coordinates from the driver.
5. A signed driver package for normal installation.

Microsoft documentation:

- [Precision Touchpad input](https://learn.microsoft.com/en-us/windows/win32/input-precisiontouchpad/precision-touchpad-portal)
- [Precision Touchpad HID collection](https://learn.microsoft.com/en-us/windows-hardware/design/component-guidelines/touchpad-windows-precision-touchpad-collection)
- [Virtual HID Framework](https://learn.microsoft.com/en-us/windows-hardware/drivers/hid/virtual-hid-framework--vhf-)

## Required Windows development setup

- Windows 10 or 11 development machine
- Visual Studio 2022 with Desktop C++ and Windows Driver Kit integration
- Matching Windows SDK and WDK
- A test-signing setup for development, or an EV certificate plus Microsoft Hardware Dev Center submission for public distribution

Never install an unsigned driver from an untrusted source. A HID filter driver runs in kernel mode and a bug can cause system instability.

## Hardware identification required before implementation

The driver needs exact hardware IDs because report formats and filter binding differ by touchpad.

On the Windows laptop:

1. Open **Device Manager**.
2. Find the touchpad under **Human Interface Devices** or **Mice and other pointing devices**.
3. Open **Properties → Details**.
4. Select **Hardware Ids** and copy the IDs.
5. Also record the laptop manufacturer, model, Windows version, and whether the touchpad is internal, USB, or Bluetooth.

For an external wireless trackpad, record the device’s Bluetooth/USB hardware ID and product name. Do not submit serial numbers.

## Planned layout

    Windows/
    ├── App/       Future WinUI 3 configuration application
    ├── Driver/    Future KMDF HID-filter and VHF virtual-device project
    └── README.md  Windows-specific requirements and support matrix

## Recommended development order

1. Support one known Windows Precision Touchpad model in test-signing mode.
2. Confirm raw contact reports and physical dimensions for that model.
3. Build the user-mode area editor and persistence layer.
4. Add VHF virtual absolute-pointer output.
5. Add controlled hardware-ID matching and a safe uninstall path.
6. Expand support only after validating each additional device descriptor.

## Current limitations

- No Windows driver source is included yet.
- No generic laptop touchpad can be claimed supported yet.
- The macOS TabPad app will not run on Windows.

Once you provide the target Windows laptop model and touchpad Hardware IDs, this folder can become the device-specific Windows driver/app project.
