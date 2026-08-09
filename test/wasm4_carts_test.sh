#!/bin/sh
set -eu

sh ./demo/wasm4/build.sh all

grep -q '^W4 ?= tmp_w4_cli/w4$' Makefile
grep -q '^W4_PORT ?= 4444$' Makefile
grep -q 'W4_PORT=$(W4_PORT) $(W4) run' Makefile
grep -q '^wasm4-cli:' Makefile
test -f tools/download_w4.sh
grep -q 'archive=w4-mac.zip' tools/download_w4.sh
grep -q 'archive=w4-linux.zip' tools/download_w4.sh
grep -q 'archive=w4-windows.zip' tools/download_w4.sh

for cart in tetromino minicraft flight snake puyo; do
  test -f "demo/wasm4/$cart.d"
  test -f "tmp_wasm4/$cart.wasm"
  test "$(od -An -tx1 -N8 "tmp_wasm4/$cart.wasm" | tr -d '[:space:]')" = 0061736d01000000
  strings "tmp_wasm4/$cart.wasm" | grep -qx start
  strings "tmp_wasm4/$cart.wasm" | grep -qx update
  strings "tmp_wasm4/$cart.wasm" | grep -qx rect
  strings "tmp_wasm4/$cart.wasm" | grep -qx memory
  od -An -tx1 "tmp_wasm4/$cart.wasm" | tr -d '[:space:]' |
    grep -q '021a0203656e760472656374000003656e76066d656d6f7279020001'
  # The allocator global is mutable i32 initialized with i32.const.  Its
  # section length varies with static game data (Snake has two 400-cell arrays).
  od -An -tx1 "tmp_wasm4/$cart.wasm" | tr -d '[:space:]' | grep -q '017f0141'
  od -An -tx1 "tmp_wasm4/$cart.wasm" | tr -d '[:space:]' | grep -q '41a0330b'
done

grep -q 'readGamepad' demo/wasm4/tetromino.d
grep -q 'readGamepad' demo/wasm4/minicraft.d
grep -q 'readGamepad' demo/wasm4/flight.d
grep -q 'int\[400\] snakeX' demo/wasm4/snake.d
grep -q 'int\[400\] snakeY' demo/wasm4/snake.d
grep -q 'fruitX' demo/wasm4/snake.d
grep -q 'ushort\[72\] board' demo/wasm4/puyo.d
grep -q 'void rotatePair' demo/wasm4/puyo.d
grep -q 'int flood' demo/wasm4/puyo.d
grep -q 'readGamepad' demo/wasm4/puyo.d

echo "PASS: D-only WASM-4 cartridges build with drawing, input, Snake, and Puyo state ABI"
