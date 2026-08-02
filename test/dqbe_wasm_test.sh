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

"$D2QBE" -t wasm32 'extern(C) int main() { int x = 7; return x; }' | "$DQBE" -t wasm32 > "$OUTPUT"
HEADER=$(od -An -tx1 -N8 "$OUTPUT" | tr -d '[:space:]')
if [ "$HEADER" != "0061736d01000000" ]; then
  echo "FAILED: wasm32 local-variable pipeline did not emit a WebAssembly binary"
  exit 1
fi

echo "PASS: d2qbe -> wasm32 supports local word storage"

"$D2QBE" -t wasm32 'extern(C) int main(int* p) { return *p; }' | "$DQBE" -t wasm32 > "$OUTPUT"
HEADER=$(od -An -tx1 -N8 "$OUTPUT" | tr -d '[:space:]')
if [ "$HEADER" != "0061736d01000000" ]; then
  echo "FAILED: wasm32 pointer-parameter pipeline did not emit a WebAssembly binary"
  exit 1
fi

echo "PASS: d2qbe -> wasm32 supports pointer parameters"

"$D2QBE" -t wasm32 'extern(C) int main() { return "x"[0]; }' | "$DQBE" -t wasm32 > "$OUTPUT"
HEADER=$(od -An -tx1 -N8 "$OUTPUT" | tr -d '[:space:]')
if [ "$HEADER" != "0061736d01000000" ]; then
  echo "FAILED: wasm32 string-literal pipeline did not emit a WebAssembly binary"
  exit 1
fi
if ! od -An -tx1 "$OUTPUT" | tr -d '[:space:]' | grep -q '2d0000'; then
  echo "FAILED: wasm32 string indexing did not use an unsigned byte load"
  exit 1
fi

echo "PASS: d2qbe -> wasm32 lowers string-literal addresses"

"$D2QBE" -t wasm32 'int g; extern(C) int main() { g = 7; return g; }' | "$DQBE" -t wasm32 > "$OUTPUT"
HEADER=$(od -An -tx1 -N8 "$OUTPUT" | tr -d '[:space:]')
if [ "$HEADER" != "0061736d01000000" ]; then
  echo "FAILED: wasm32 mutable-global pipeline did not emit a WebAssembly binary"
  exit 1
fi

echo "PASS: d2qbe -> wasm32 lowers mutable globals"

"$D2QBE" -t wasm32 'extern(C) void touch(int* p) { *p = 42; } extern(C) int main() { int x; touch(&x); return x; }' | "$DQBE" -t wasm32 > "$OUTPUT"
HEADER=$(od -An -tx1 -N8 "$OUTPUT" | tr -d '[:space:]')
if [ "$HEADER" != "0061736d01000000" ]; then
  echo "FAILED: wasm32 void-call pipeline did not emit a WebAssembly binary"
  exit 1
fi

echo "PASS: d2qbe -> wasm32 supports internal void calls"

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

printf '%s\n' \
  'data $answer = { b 42 }' \
  'export function w $main() {' \
  '@start' \
  '  %address =w copy $answer' \
  '  ret %address' \
  '}' | "$DQBE" -t wasm32 > "$OUTPUT"
BYTES=$(od -An -tx1 "$OUTPUT" | tr -d '[:space:]')
if ! printf '%s' "$BYTES" | grep -q '0b07010041000b012a'; then
  echo "FAILED: static byte data was not emitted as an active Wasm segment"
  exit 1
fi

echo "PASS: dqbe -t wasm32 emits static data segments"
