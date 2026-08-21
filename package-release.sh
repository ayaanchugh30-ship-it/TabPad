#!/bin/bash
set -euo pipefail

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
app_path="$root_dir/TabPad.app"
archive_path="$root_dir/TabPad.app.zip"

"$root_dir/scripts/build-app.sh"
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$archive_path"
echo "Created $archive_path"
