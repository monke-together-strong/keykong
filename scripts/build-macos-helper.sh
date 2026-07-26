#!/bin/sh
set -eu

root=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
cd "$root"

swift build \
  --package-path native/macos \
  -c release \
  --product keykong-prompt

bundle=dist/libexec/KeyKongPrompt.app
contents=$bundle/Contents
executable=$contents/MacOS/keykong-prompt
resources=$contents/Resources
icon=$resources/KeyKong.icns
icon_source=assets/keykong-app-icon-emblem.png
plist=$contents/Info.plist
version=$(/usr/bin/plutil -extract version raw package.json)
icon_work_dir=$(mktemp -d)
iconset=$icon_work_dir/KeyKong.iconset

cleanup() {
  rm -rf "$icon_work_dir"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

rm -rf "$bundle"
mkdir -p "$contents/MacOS" "$resources" "$iconset"
cp native/macos/.build/release/keykong-prompt "$executable"
cp "$icon_source" "$resources/keykong-app-icon-emblem.png"

/usr/bin/sips -z 16 16 "$icon_source" --out "$iconset/icon_16x16.png" >/dev/null
/usr/bin/sips -z 32 32 "$icon_source" --out "$iconset/icon_16x16@2x.png" >/dev/null
/usr/bin/sips -z 32 32 "$icon_source" --out "$iconset/icon_32x32.png" >/dev/null
/usr/bin/sips -z 64 64 "$icon_source" --out "$iconset/icon_32x32@2x.png" >/dev/null
/usr/bin/sips -z 128 128 "$icon_source" --out "$iconset/icon_128x128.png" >/dev/null
/usr/bin/sips -z 256 256 "$icon_source" --out "$iconset/icon_128x128@2x.png" >/dev/null
/usr/bin/sips -z 256 256 "$icon_source" --out "$iconset/icon_256x256.png" >/dev/null
/usr/bin/sips -z 512 512 "$icon_source" --out "$iconset/icon_256x256@2x.png" >/dev/null
/usr/bin/sips -z 512 512 "$icon_source" --out "$iconset/icon_512x512.png" >/dev/null
/usr/bin/sips -z 1024 1024 "$icon_source" --out "$iconset/icon_512x512@2x.png" >/dev/null
/usr/bin/iconutil -c icns -o "$icon" "$iconset"

/usr/bin/plutil -create xml1 "$plist"
/usr/bin/plutil -insert CFBundleDisplayName -string KeyKong "$plist"
/usr/bin/plutil -insert CFBundleExecutable -string keykong-prompt "$plist"
/usr/bin/plutil -insert CFBundleIconFile -string KeyKong.icns "$plist"
/usr/bin/plutil -insert CFBundleIdentifier -string dev.keykong.prompt "$plist"
/usr/bin/plutil -insert CFBundleInfoDictionaryVersion -string 6.0 "$plist"
/usr/bin/plutil -insert CFBundleName -string KeyKong "$plist"
/usr/bin/plutil -insert CFBundlePackageType -string APPL "$plist"
/usr/bin/plutil -insert CFBundleShortVersionString -string "$version" "$plist"
/usr/bin/plutil -insert CFBundleVersion -string "$version" "$plist"
/usr/bin/plutil -insert LSMinimumSystemVersion -string 13.0 "$plist"
/usr/bin/plutil -insert NSPrincipalClass -string NSApplication "$plist"
