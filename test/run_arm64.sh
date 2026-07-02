#!/bin/bash


D2QBE=${D2QBE:-./d2qbe}
QBE=${QBE:-./dqbe}
ARCH=$(uname -m)

if [ "$ARCH" != "arm64" ] && [ "$ARCH" != "aarch64" ]; then
  echo "Skipping ARM64 integration tests (host is $ARCH)"
  exit 0
fi

if [ "$OS" = "Windows_NT" ]; then
  OBJ_EXT="obj"
else
  OBJ_EXT="o"
fi

assert_v2() {
  expected="$1"
  input="$2"

  if [ "$(uname -s)" = "Darwin" ]; then
    TARGET="arm64_apple"
  else
    TARGET="arm64"
  fi
  $D2QBE "$input" | $QBE -t $TARGET > tmp.s
  cat tmp.s
  cc -o tmp tmp.s ext.${OBJ_EXT}
  actual_output=$(./tmp)
  actual="$?"

  if [ "$actual" = "$expected" ]; then
    echo "SUCCESS"
  else
    echo "FAILED: $expected expected, but got $actual"
    exit 1
  fi
}

echo "=== Running subset of ARM64 integration tests ==="

# Test 1: Simple return exit code 0
assert_v2 0 "extern(C) int main() { return 0; }"

# Test 2: Simple return exit code 42
assert_v2 42 "extern(C) int main() { return 42; }"

rm -f tmp tmp.s
echo "All ARM64 subset tests passed!"
