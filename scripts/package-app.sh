#!/bin/zsh
set -euo pipefail

configuration="${1:-debug}"
repo_root="${0:A:h:h}"
cd "$repo_root"

swift_command=(swift)
if ! swift --version >/dev/null 2>&1; then
    swift_command=(env DEVELOPER_DIR=/Library/Developer/CommandLineTools swift)
fi

"${swift_command[@]}" build --configuration "$configuration" --product PodStick
binary_dir="$("${swift_command[@]}" build --configuration "$configuration" --show-bin-path)"
app_path="$repo_root/.build/PodStick.app"

case "$app_path" in
    "$repo_root/.build/PodStick.app") ;;
    *) print -u2 "Refusing to replace unexpected path: $app_path"; exit 1 ;;
esac

rm -rf "$app_path"
mkdir -p "$app_path/Contents/MacOS"
cp "$binary_dir/PodStick" "$app_path/Contents/MacOS/PodStick"
cp "$repo_root/Resources/Info.plist" "$app_path/Contents/Info.plist"
codesign --force --sign - "$app_path"

print "$app_path"
