#!/bin/sh
set -eu

sh ./demo/wasm4/build.sh all

for cart in tetromino minicraft flight; do
  test -f "demo/wasm4/$cart.d"
  test -f "tmp_wasm4/$cart.wasm"
  test "$(od -An -tx1 -N8 "tmp_wasm4/$cart.wasm" | tr -d '[:space:]')" = 0061736d01000000
  strings "tmp_wasm4/$cart.wasm" | grep -qx start
  strings "tmp_wasm4/$cart.wasm" | grep -qx update
  strings "tmp_wasm4/$cart.wasm" | grep -qx rect
  strings "tmp_wasm4/$cart.wasm" | grep -qx memory
  od -An -tx1 "tmp_wasm4/$cart.wasm" | tr -d '[:space:]' |
    grep -q '021a0203656e760472656374000003656e76066d656d6f7279020001'
  od -An -tx1 "tmp_wasm4/$cart.wasm" | tr -d '[:space:]' | grep -q '41a0330b'
done

grep -q 'readGamepad' demo/wasm4/tetromino.d
grep -q 'readGamepad' demo/wasm4/minicraft.d
grep -q 'readGamepad' demo/wasm4/flight.d

echo "PASS: D-only WASM-4 cartridges build with drawing and input ABI"
