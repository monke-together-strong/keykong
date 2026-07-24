#!/bin/sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repository_root"

bun run build
bun run build:helper

signing_identity=${KEY_KONG_CODESIGN_IDENTITY:--}
codesign \
  --entitlements scripts/bun-entitlements.plist \
  --deep \
  --force \
  --sign "$signing_identity" \
  dist/bin/key-kong
codesign --force --sign "$signing_identity" dist/libexec/key-kong-prompt
codesign --verify --verbose=3 dist/bin/key-kong
codesign --verify --strict dist/libexec/key-kong-prompt
