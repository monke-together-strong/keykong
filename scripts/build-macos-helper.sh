#!/bin/sh
set -eu

root=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
cd "$root"

swift build \
  --package-path native/macos \
  -c release \
  --product key-kong-prompt

bundle=dist/libexec/KeyKongPrompt.app
contents=$bundle/Contents
executable=$contents/MacOS/key-kong-prompt
plist=$contents/Info.plist
version=$(/usr/bin/plutil -extract version raw package.json)

rm -rf "$bundle"
mkdir -p "$contents/MacOS"
cp native/macos/.build/release/key-kong-prompt "$executable"

/usr/bin/plutil -create xml1 "$plist"
/usr/bin/plutil -insert CFBundleDisplayName -string KeyKong "$plist"
/usr/bin/plutil -insert CFBundleExecutable -string key-kong-prompt "$plist"
/usr/bin/plutil -insert CFBundleIdentifier -string dev.keykong.prompt "$plist"
/usr/bin/plutil -insert CFBundleInfoDictionaryVersion -string 6.0 "$plist"
/usr/bin/plutil -insert CFBundleName -string KeyKong "$plist"
/usr/bin/plutil -insert CFBundlePackageType -string APPL "$plist"
/usr/bin/plutil -insert CFBundleShortVersionString -string "$version" "$plist"
/usr/bin/plutil -insert CFBundleVersion -string "$version" "$plist"
/usr/bin/plutil -insert LSMinimumSystemVersion -string 13.0 "$plist"
/usr/bin/plutil -insert NSPrincipalClass -string NSApplication "$plist"
