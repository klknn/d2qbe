#!/bin/bash
set -e

./test/wasm_browser/build.sh test

test -f tmp_wasm_browser/manifest.json
test -f tmp_wasm_browser/direct_return.wasm
test -f tmp_wasm_browser/host_import.wasm
test -f tmp_wasm_browser/allocator_growth.wasm
test -f test/wasm_browser/test.html
test -f test/wasm_browser/demo.html

grep -q 'WebAssembly.instantiate' test/wasm_browser/test.html
grep -q 'host_increment' test/wasm_browser/test.html
grep -q 'input type="range"' test/wasm_browser/demo.html
grep -q 'WASM_BROWSER_OPEN' test/wasm_browser/serve.sh
grep -q '"allocator_growth"' tmp_wasm_browser/manifest.json

echo "PASS: browser Wasm fixtures and pages are available"
