#!/bin/sh
set -eu

rm -rf dist/bin dist/libexec
bun run build
bun run build:helper

identity=${KEY_KONG_SIGNING_IDENTITY:--}
for executable in dist/bin/key-kong dist/libexec/key-kong-prompt; do
  if [ "$identity" = "-" ]; then
    codesign --force --sign - "$executable"
  else
    codesign --force --timestamp --sign "$identity" "$executable"
  fi
  codesign --verify --strict --verbose=2 "$executable"
done

bun scripts/smoke-package.ts
