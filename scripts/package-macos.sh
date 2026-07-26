#!/bin/sh
set -eu

rm -rf dist
bun run build
bun run build:helper

identity=${KEY_KONG_SIGNING_IDENTITY:--}
if [ "$identity" = "-" ]; then
  echo "warning: KEY_KONG_SIGNING_IDENTITY unset; using an ad-hoc hardened signature" >&2
fi
app=dist/libexec/KeyKongPrompt.app
helper=$app/Contents/MacOS/keykong-prompt

sign() {
  target=$1
  if [ "$identity" = "-" ]; then
    codesign --force --options runtime --sign - "$target"
  else
    codesign --force --timestamp --options runtime --sign "$identity" "$target"
  fi
}

sign "$helper"
sign "$app"
sign dist/bin/keykong

codesign --verify --strict --verbose=2 "$helper"
codesign --verify --deep --strict --verbose=2 "$app"
codesign --verify --strict --verbose=2 dist/bin/keykong

bun scripts/smoke-package.ts
