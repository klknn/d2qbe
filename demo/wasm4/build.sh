#!/bin/sh
set -eu

MODE=${1:?"usage: build.sh <all|tetromino|minicraft|flight|snake|puyo>"}
D2QBE=${D2QBE:-./d2qbe}
DQBE=${DQBE:-./dqbe}
OUTPUT=tmp_wasm4

mkdir -p "$OUTPUT"

build_cart() {
  name=$1
  source="$(sed -n '1,$p' demo/wasm4/wasm4.d)
$(sed -n '1,$p' "demo/wasm4/$name.d")"
  "$D2QBE" -t wasm4 "$source" | "$DQBE" -t wasm4 > "$OUTPUT/$name.wasm"
  printf 'Built D-only WASM-4 cartridge: %s\n' "$OUTPUT/$name.wasm"
}

case "$MODE" in
  all) build_cart tetromino; build_cart minicraft; build_cart flight; build_cart snake; build_cart puyo ;;
  tetromino|minicraft|flight|snake|puyo) build_cart "$MODE" ;;
  *) echo "unknown WASM-4 cartridge: $MODE" >&2; exit 2 ;;
esac
