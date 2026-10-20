#!/bin/sh
set -eu

root_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
install_bin="${HOME:?}/.local/bin"
install_libexec="${HOME:?}/.local/libexec"
target_cli="$install_bin/keykong"
target_app="$install_libexec/KeyKongPrompt.app"

mkdir -p "$install_bin" "$install_libexec"
staging_dir=$(mktemp -d "$install_libexec/.keykong-install.XXXXXX")

cleanup() {
  rm -rf -- "$staging_dir"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

cd "$root_dir"
if [ "$(uname -s)" = Darwin ]; then
  bun run package:macos
  cp -R "dist/libexec/KeyKongPrompt.app" "$staging_dir/KeyKongPrompt.app"
  rm -rf -- "$target_app"
  mv "$staging_dir/KeyKongPrompt.app" "$target_app"
else
  # Without the native prompt, use `keykong prompt web`.
  bun run build
fi

cp "dist/bin/keykong" "$staging_dir/keykong"
chmod +x "$staging_dir/keykong"
mv "$staging_dir/keykong" "$target_cli"

printf 'Installed keykong to %s\n' "$target_cli"
