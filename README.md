# TabPad

Turn a Mac trackpad into a one-finger absolute pointing surface for osu!. TabPad maps each physical trackpad position to one fixed screen position, like a drawing tablet.

## If you only want the app

On the GitHub **Releases** page, download:

> **TabPad.app.zip**

Do **not** download **Source code (zip)** or **Source code (tar.gz)** unless you want to build TabPad yourself.

To install:

1. Double-click TabPad.app.zip to unzip it.
2. Drag **TabPad.app** to your Applications folder, or another permanent folder you control.
3. Open TabPad.app.
4. If macOS blocks the first launch, Control-click TabPad.app, choose **Open**, then choose **Open** again.
5. Grant Accessibility permission when TabPad asks.

Thats everything a normal user needs. You dont need Xcode, Terminal, or any files from this repository.

## What TabPad does

- Reads raw contacts from Apple multitouch trackpads
- Maps a chosen trackpad area to a selected display
- Lets you aim with one finger in absolute mode
- Provides an interactive area editor, typed numeric values, millimeter mode, aspect-ratio lock, and centering
- Shows the live finger position and detected hardware
- Saves the selected active area across launches
- Applies a no-lag micro dead-zone and limits synthetic mouse events to reduce shake and osu!lazer input flooding
- Provides an Input filtering toggle: turn it off for direct raw, lowest-latency contact output

TabPad works as a macOS pointer utility. It does **not** emulate a native hardware drawing tablet or provide click input; use keyboard keys for osu! clicks.

## Requirements

- macOS 13 or later
- Apple Silicon or Intel Mac
- A built-in Apple trackpad or supported Apple multitouch trackpad, like as a Magic Trackpad
- Accessibility permission
- For building from source: Xcode or Xcode Command Line Tools

## Install and launch

### Use the built app

Open TabPad.app in Finder. Keep the app in a stable location; moving or rebuilding an ad-hoc signed app can cause macOS to request Accessibility permission again. You can copy this single app bundle elsewhere without taking the source repository.

### Build from source

From the repository root, run:

    chmod +x scripts/build-app.sh
    scripts/build-app.sh
    open TabPad.app

The build script creates and signs a local TabPad.app bundle at the repository root.

### Create a GitHub release download

After building, run:

    scripts/package-release.sh

This creates TabPad.app.zip. Upload **that ZIP file** to a GitHub Release so users can follow the short installation instructions above.

## Grant Accessibility permission

TabPad needs Accessibility permission to filter physical trackpad motion and send its mapped pointer events.

1. Open TabPad.
2. Click **Open Accessibility Settings** if the app shows the permission message.
3. In **System Settings → Privacy & Security → Accessibility**, add or enable the exact TabPad.app bundle you launched.
4. Return to TabPad. It detects the change automatically; no relaunch is normally needed.

If permission still does not work, remove any old TabPad entries in Accessibility, add the current app bundle again, and turn it on.

## Basic osu! setup

1. Open TabPad and select the display that osu! uses.
2. Leave **Use full trackpad** selected for your first test.
3. Turn on **Enable absolute tablet mode**.
4. Move one finger on the trackpad: each position should map directly to a screen position.
5. Use your preferred keyboard keys to click notes.
6. Turn tablet mode off before returning to regular Mac use.

## osu!lazer setup

TabPad supplies absolute **mouse** events rather than a native tablet device.

In osu!lazer’s Input settings:

- Turn **High Precision Mouse** off.
- Turn **Tablet input** off.
- Keep osu!lazer focused while testing.

If lazer stutters, fully quit any older TabPad instance and launch the newest build. TabPad coalesces pointer output to 240 Hz to avoid flooding the game’s input queue without adding noticeable aim latency.

When TabPad is not the frontmost app, its live-preview UI automatically pauses. The raw input bridge remains active, but the SwiftUI preview no longer uses resources during gameplay.

### Input filtering and latency

**Input filtering** is enabled by default. It rejects sub-pixel shake and caps output at 240 Hz. Turn it **off** for the lowest possible latency: TabPad sends every raw contact immediately, with no dead-zone or event-rate cap. If that creates jitter or lazer stutter, turn filtering back on.

## Trackpad area editor

The blue rectangle is the active part of the trackpad. Only this rectangle maps to the full selected display.

- **Drag the blue rectangle** to move the active area.
- **Drag a corner handle** to resize it.
- **Center area** keeps the current size and centers it on the trackpad.
- **Use full trackpad** restores the complete surface.
- The **green dot** shows your current one-finger contact.

The area saves automatically at:

    ~/Library/Application Support/TabPad/area.json

## Numeric area controls

The Left, Top, Width, and Height boxes accept typed values and expand for longer numbers.

### Percent mode

Uses 0–100% of the active trackpad surface. This is the most portable option between different trackpads.

### Millimeters mode

Uses the physical dimensions reported by the trackpad currently being touched. For example, enter 25 in Width and Height for a 25 mm × 25 mm area.

Millimeter values are device-specific. If you switch from the built-in trackpad to a Magic Trackpad, touch the new device first so TabPad refreshes the reported dimensions.

### Limits

- Width and Height accept any positive value up to the current trackpad’s reported maximum.
- Left and Top can be zero and are limited to the remaining usable area.
- Decimal values are supported.

## Aspect-ratio lock

Enable **Lock aspect ratio** and enter a ratio such as:

- 1:1 for a square
- 4:3 for a standard display proportion
- 16:9 for widescreen
- 9:16 for a tall area

While locked, changing Width or Height adjusts the other dimension, and corner resizing preserves the selected physical ratio.

## Orientation

- **Mirror horizontally** flips left and right.
- **Invert vertical axis** flips up and down.

These settings affect the aiming map, not the visual orientation of the editor’s green finger tracker.

## External trackpads

TabPad enumerates Apple multitouch devices, including wireless Magic Trackpads. The **Detected hardware** section lists the Mac model and recognized connected trackpads.

If a wireless trackpad is not listed:

1. Confirm it is connected and working in macOS Bluetooth settings.
2. Click **Refresh hardware** in TabPad.
3. Quit and reopen TabPad after connecting the device.

An Apple Pencil or other stylus is not a trackpad contact device and cannot be read by this project.

## Troubleshooting

### The cursor does not move

- Confirm TabPad says **Ready** or **Tablet mode is on**.
- Grant Accessibility permission to the exact current TabPad.app bundle.
- Test with tablet mode on outside osu! first.

### osu!lazer does not respond

- Disable High Precision Mouse and Tablet input in lazer.
- Confirm TabPad works in another application before testing lazer.
- Run only one TabPad copy at a time.

### osu!lazer stutters

- Update to the latest TabPad build.
- Turn tablet mode off and confirm the stutter stops.
- Ensure another input remapper is not sending duplicate mouse events.
- Test in windowed or borderless mode if fullscreen cursor confinement interferes.

### The active area resets

Check that TabPad displays **Area saved** after editing. Its settings file is at ~/Library/Application Support/TabPad/area.json; make sure the user account can write to that location.

### Millimeter mode is unavailable or wrong

The private macOS multitouch API may not report a physical size for every device or macOS version. Use Percent mode when no valid sensor dimensions appear. For a connected external trackpad, touch it once before entering mm values.

## Privacy and limitations

TabPad uses Apple’s undocumented MultitouchSupport.framework. That means:

- It is intended for personal/local use.
- It cannot be reliably distributed through the Mac App Store.
- A future macOS release may change or remove the private API.
- It is macOS-only; it does not work on Windows.

The project intentionally loads the private framework at runtime and reports an incompatibility error instead of crashing if it cannot be used.

## Contributing and bug reports

Use the included GitHub bug-report template. Please include:

- macOS version
- Mac model shown by TabPad
- Connected trackpad name and transport
- Whether the problem occurs with tablet mode on or off
- Whether osu!lazer is affected

Do not include serial numbers, account details, or private device identifiers.

## Repository layout

    Assets/                 App icon source PNG and macOS .icns file
    Sources/TabPad/         SwiftUI application
    Sources/TrackpadBridge/ C bridge for raw multitouch and pointer events
    scripts/build-app.sh    Builds and signs the local .app bundle
    scripts/package-release.sh Creates the GitHub release ZIP
    TabPad.app              Generated standalone app bundle (ignored by Git)
