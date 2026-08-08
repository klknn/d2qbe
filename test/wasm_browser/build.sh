#!/bin/bash
set -euo pipefail

MODE=${1:?"usage: build.sh <test|demo|game>"}
D2QBE=${D2QBE:-./d2qbe}
DQBE=${DQBE:-./dqbe}
OUTPUT=tmp_wasm_browser

mkdir -p "$OUTPUT"

append_case() {
  local name=$1
  local expected=$2
  local args=$3
  local minimum_pages=$4

  if [ "$manifest_first" = true ]; then
    manifest_first=false
  else
    printf ',' >> "$OUTPUT/manifest.json"
  fi
  printf '{"name":"%s","expected":%s,"args":%s,"minimumPages":%s,"module":"%s.wasm"}' \
    "$name" "$expected" "$args" "$minimum_pages" "$name" >> "$OUTPUT/manifest.json"
}

emit_d_case() {
  local name=$1
  local expected=$2
  local args=$3
  local minimum_pages=$4
  local source=$5

  "$D2QBE" -t wasm32 "$source" | "$DQBE" -t wasm32 > "$OUTPUT/$name.wasm"
  append_case "$name" "$expected" "$args" "$minimum_pages"
}

emit_qbe_case() {
  local name=$1
  local expected=$2
  local args=$3
  local minimum_pages=$4
  local source=$5

  printf '%s' "$source" | "$DQBE" -t wasm32 > "$OUTPUT/$name.wasm"
  append_case "$name" "$expected" "$args" "$minimum_pages"
}

case "$MODE" in
  test)
    printf '{"cases":[' > "$OUTPUT/manifest.json"
    manifest_first=true

    emit_qbe_case direct_return 42 '[]' 0 $'export function w $main() {\n@start\n  ret 42\n}\n'
    emit_d_case d_return_42 42 '[]' 0 'extern(C) int main() { return 42; }'
    emit_d_case pointer_size 4 '[]' 0 'extern(C) int main() { return int*.sizeof; }'
    emit_d_case local_word 7 '[]' 1 'extern(C) int main() { int value = 7; return value; }'
    emit_d_case pointer_parameter 0 '[0]' 1 'extern(C) int main(int* value) { return *value; }'
    emit_d_case pointer_arithmetic 1 '[]' 1 'extern(C) int main() { int value = 42; int* pointer = &value; return (pointer + 1) - pointer; }'
    emit_d_case string_byte 120 '[]' 1 'extern(C) int main() { return "x"[0]; }'
    emit_d_case global_word 7 '[]' 1 'int value; extern(C) int main() { value = 7; return value; }'
    emit_d_case void_call 42 '[]' 1 'extern(C) void touch(int* value) { *value = 42; } extern(C) int main() { int value; touch(&value); return value; }'
    emit_d_case result_call 42 '[]' 0 'extern(C) int increment(int value) { return value + 1; } extern(C) int main() { return increment(41); }'
    emit_d_case host_import 42 '[]' 0 'extern(C) int host_increment(int value); extern(C) void host_log(int value); extern(C) int main() { int value = host_increment(41); host_log(value); return value; }'
    emit_d_case pointer_result_import 0 '[]' 1 'extern(C) int* host_alloc(int count); extern(C) int main() { int* value = host_alloc(1); return *value; }'
    emit_d_case pointer_cast 0 '[]' 0 'extern(C) void host_ptr(int* value); extern(C) int main() { host_ptr(cast(int*) 0); return 0; }'
    emit_d_case struct_members 42 '[]' 1 'struct Pair { int left; int right; } extern(C) int main() { Pair pair; pair.left = 40; pair.right = 2; return pair.left + pair.right; }'
    emit_d_case byte_storage 65 '[]' 1 'extern(C) int main() { char value = 65; return value; }'
    emit_qbe_case conditional_branch 42 '[1]' 0 $'export function w $main(w %condition) {\n@start\n  jnz %condition, @then, @else\n@then\n  ret 42\n@else\n  ret 7\n}\n'
    emit_qbe_case unconditional_branch 42 '[]' 0 $'export function w $main() {\n@start\n  jmp @result\n@unreachable\n  ret 0\n@result\n  ret 42\n}\n'
    emit_qbe_case word_memory 42 '[]' 1 $'export function w $main() {\n@start\n  %addr =w copy 0\n  storew 42, %addr\n  %value =w loadw %addr\n  ret %value\n}\n'
    emit_qbe_case static_data 0 '[]' 1 $'data $answer = { b 42 }\nexport function w $main() {\n@start\n  %address =w copy $answer\n  ret %address\n}\n'
    emit_qbe_case allocator_growth 0 '[]' 2 $'export function w $main() {\n@start\n  %address =w alloc4 70000\n  ret %address\n}\n'

    printf ']}\n' >> "$OUTPUT/manifest.json"
    printf 'Built browser test fixtures in %s\n' "$OUTPUT"
    ;;
  demo)
    "$D2QBE" -t wasm32 \
      'extern(C) int host_value(); extern(C) int main() { int value = host_value(); return value * value + 1; }' \
      | "$DQBE" -t wasm32 > "$OUTPUT/demo.wasm"
    printf 'Built browser demo module in %s\n' "$OUTPUT"
    ;;
  game)
    "$D2QBE" -t wasm32 \
      'extern(C) int main(int lines, int level, int combo) { return lines * 100 + level * 50 + combo * 25; }' \
      | "$DQBE" -t wasm32 > "$OUTPUT/game.wasm"
    printf 'Built browser game module in %s\n' "$OUTPUT"
    ;;
  *)
    echo "unknown browser build mode: $MODE" >&2
    exit 2
    ;;
esac
