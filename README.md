# TabPad

TabPad turns a MacBook trackpad into a one-finger absolute pointing surface for osu!. It is a native SwiftUI app with a small C bridge that reads raw trackpad contact positions and posts mapped absolute mouse-move events.

> **GitHub description:** Turn a Mac trackpad into an absolute osu! tablet surface.

It listens to Apple multitouch devices exposed by macOS, including a connected wireless Magic Trackpad. The physical millimeter dimensions change to match the surface that is currently touched.

For osu!lazer, disable **High Precision Mouse** and **Tablet input** in its Input settings. TabPad emits regular absolute mouse-move events; it does not install a virtual tablet driver.

## Build and run

```bash
chmod +x scripts/build-app.sh
scripts/build-app.sh
open outputs/TabPad.app
```

At first launch, allow **Accessibility** access in System Settings → Privacy & Security → Accessibility, quit the app, and launch it again. Select the target monitor, optionally crop the active pad area, then enable tablet mode. Use keyboard keys for osu! clicks.

## Features

- Absolute one-finger aiming with selectable display mapping
- Interactive area editor, numerical percent/mm entry, aspect-ratio lock, and centering
- Live finger-position preview and connected-trackpad detection
- Area persistence across launches
- Small jitter dead-zone and output coalescing for small-area stability
- osu!lazer-compatible regular mouse events

## osu!lazer setup

In osu!lazer's Input settings, turn **High Precision Mouse** and **Tablet input** off. TabPad supplies absolute mouse events, rather than registering as a hardware tablet.

## Requirements

- macOS 13 or later
- A built-in Apple trackpad or supported Apple multitouch trackpad (for example Magic Trackpad)
- Accessibility permission
- Xcode Command Line Tools or Xcode for local builds

## Important limitation

`MultitouchSupport.framework` is an undocumented Apple private framework. It is suitable for a personal local build but cannot be reliably distributed through the Mac App Store and could require maintenance after a macOS update. This app deliberately loads it at runtime and reports a clear incompatibility error instead of crashing.

## Contributing

Bug reports are welcome. Include your macOS version, Mac model, connected-trackpad name, and whether the issue occurs with tablet mode on or off. Do not include private logs or device identifiers.
