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
bun run package:macos

cp "dist/bin/keykong" "$staging_dir/keykong"
cp -R "dist/libexec/KeyKongPrompt.app" "$staging_dir/KeyKongPrompt.app"
chmod +x "$staging_dir/keykong"

rm -rf -- "$target_app"
mv "$staging_dir/KeyKongPrompt.app" "$target_app"
mv "$staging_dir/keykong" "$target_cli"

printf 'Installed keykong to %s\n' "$target_cli"
