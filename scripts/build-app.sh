#!/bin/bash
set -euo pipefail

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
output_dir="$root_dir/TabPad.app"
scratch_dir="/private/tmp/tabpad-swift-build"
cache_dir="/private/tmp/tabpad-module-cache"
icon_file="$root_dir/Assets/TabPad.icns"

mkdir -p "$cache_dir" "$scratch_dir"
# The package has no dependencies or build plugins. Disabling SwiftPM's manifest sandbox
# also makes this work in restricted development shells where sandbox-exec is unavailable.
CLANG_MODULE_CACHE_PATH="$cache_dir" SWIFTPM_MODULECACHE_OVERRIDE="$cache_dir" swift build --disable-sandbox --scratch-path "$scratch_dir" -c release --package-path "$root_dir"
binary_path="$(find "$scratch_dir" -path '*/release/TabPad' -type f -print -quit)"
if [ -z "$binary_path" ]; then
  echo "Could not locate the built TabPad executable." >&2
  exit 1
fi
rm -rf "$output_dir"
mkdir -p "$output_dir/Contents/MacOS" "$output_dir/Contents/Resources"
cp "$binary_path" "$output_dir/Contents/MacOS/TabPad"
cp "$icon_file" "$output_dir/Contents/Resources/TabPad.icns"
cat > "$output_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>TabPad</string>
<key>CFBundleIdentifier</key><string>local.tabpad.osu</string>
<key>CFBundleName</key><string>TabPad</string>
<key>CFBundleDisplayName</key><string>TabPad</string>
<key>CFBundleIconFile</key><string>TabPad</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
</dict></plist>
PLIST
codesign --force --sign - "$output_dir"
echo "Built $output_dir"
