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

"$D2QBE" 'extern(C) int main() { return 42; }' | "$DQBE" -t wasm32 > "$OUTPUT"
HEADER=$(od -An -tx1 -N8 "$OUTPUT" | tr -d '[:space:]')
if [ "$HEADER" != "0061736d01000000" ]; then
  echo "FAILED: d2qbe pipeline did not emit a WebAssembly binary"
  exit 1
fi

echo "PASS: d2qbe -> dqbe -t wasm32 smoke test"
