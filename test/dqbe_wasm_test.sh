#!/bin/bash
set -e

DQBE=${DQBE:-./dqbe}
D2QBE=${D2QBE:-./d2qbe}
OUTPUT=tmp_dqbe_wasm.wasm

trap 'rm -f "$OUTPUT"' EXIT

printf '%s\n' \
  'export function w $main() {' \
  '@start' \
  '  ret 42' \
  '}' | "$DQBE" -t wasm32 > "$OUTPUT"

HEADER=$(od -An -tx1 -N8 "$OUTPUT" | tr -d '[:space:]')
if [ "$HEADER" != "0061736d01000000" ]; then
  echo "FAILED: expected WebAssembly magic and version, got $HEADER"
  exit 1
fi

echo "PASS: dqbe -t wasm32 emits a WebAssembly binary"

"$D2QBE" -t wasm32 'extern(C) int main() { return 42; }' | "$DQBE" -t wasm32 > "$OUTPUT"
HEADER=$(od -An -tx1 -N8 "$OUTPUT" | tr -d '[:space:]')
if [ "$HEADER" != "0061736d01000000" ]; then
  echo "FAILED: d2qbe pipeline did not emit a WebAssembly binary"
  exit 1
fi

echo "PASS: d2qbe -> dqbe -t wasm32 smoke test"

"$D2QBE" -t wasm32 'extern(C) int main() { return int*.sizeof; }' | "$DQBE" -t wasm32 > "$OUTPUT"
if ! od -An -tx1 "$OUTPUT" | tr -d '[:space:]' | grep -q '41042100'; then
  echo "FAILED: wasm32 frontend layout did not emit a four-byte pointer size"
  exit 1
fi

echo "PASS: d2qbe -t wasm32 uses wasm32 pointer layout"

printf '%s\n' \
  'export function w $main(w %condition) {' \
  '@start' \
  '  jnz %condition, @then, @else' \
  '@then' \
  '  ret 42' \
  '@else' \
  '  ret 7' \
  '}' | "$DQBE" -t wasm32 > "$OUTPUT"
HEADER=$(od -An -tx1 -N8 "$OUTPUT" | tr -d '[:space:]')
if [ "$HEADER" != "0061736d01000000" ]; then
  echo "FAILED: control-flow module did not emit a WebAssembly binary"
  exit 1
fi

echo "PASS: dqbe -t wasm32 lowers conditional control flow"

printf '%s\n' \
  'export function w $main() {' \
  '@start' \
  '  %addr =w copy 0' \
  '  storew 42, %addr' \
  '  %value =w loadw %addr' \
  '  ret %value' \
  '}' | "$DQBE" -t wasm32 > "$OUTPUT"
BYTES=$(od -An -tx1 "$OUTPUT" | tr -d '[:space:]')
if ! printf '%s' "$BYTES" | grep -q '0503010001'; then
  echo "FAILED: memory module has no one-page Wasm memory section"
  exit 1
fi
if ! printf '%s' "$BYTES" | grep -q '360200.*280200'; then
  echo "FAILED: memory module is missing i32.store/i32.load instructions"
  exit 1
fi

echo "PASS: dqbe -t wasm32 lowers w-addressed memory operations"
