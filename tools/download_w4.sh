#!/bin/sh
set -eu

DESTINATION=${1:-tmp_w4_cli}
RELEASE_BASE=${W4_RELEASE_BASE:-https://github.com/aduros/wasm4/releases/latest/download}

case "${OS:-$(uname -s)}" in
  Darwin) archive=w4-mac.zip; executable=w4 ;;
  Linux) archive=w4-linux.zip; executable=w4 ;;
  Windows_NT|MINGW*|MSYS*) archive=w4-windows.zip; executable=w4.exe ;;
  *) echo "unsupported platform for the official WASM-4 CLI: $(uname -s)" >&2; exit 2 ;;
esac

mkdir -p "$DESTINATION"
curl -fL --retry 3 "$RELEASE_BASE/$archive" -o "$DESTINATION/$archive"
unzip -o "$DESTINATION/$archive" -d "$DESTINATION"
chmod +x "$DESTINATION/$executable"
printf 'WASM-4 CLI ready: %s/%s\n' "$DESTINATION" "$executable"
