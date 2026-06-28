#!/bin/bash

D2QBE=${D2QBE:-./d2qbe}
QBE=${QBE:-./qbe/qbe}

if [ "$OS" = "Windows_NT" ]; then
  OBJ_EXT="obj"
else
  OBJ_EXT="o"
fi

assert_v2() {
  expected="$1"
  input="$2"
  output="$3"

  $D2QBE "$input" | $QBE > tmp.s
  cc -o tmp tmp.s ext.${OBJ_EXT}
  actual_output=$(./tmp)
  actual="$?"

  if [ "$actual" = "$expected" ]; then
    echo "SUCCESS"
  else
    echo "FAILED: $expected expected, but got $actual"
    exit 1
  fi
  if [ -n "$output" ]; then
    if [ "$actual_output" != "$output" ]; then
      echo "stdout mismatch: $output expected, but got $actual_output"
      exit 1
    fi
  fi
}

assert_compile_fail() {
  input="$1"
  $D2QBE "$input" > /dev/null 2>&1
  actual="$?"
  if [ "$actual" = 0 ]; then
    echo "FAILED: Compilation expected to fail, but succeeded for: $input"
    exit 1
  else
    echo "SUCCESS (compile fail)"
  fi
}

# ==============================================================================
# Modern Phased Integration Tests
# ==============================================================================
assert_v2 0 "$(cat test/arith_test.d)"
assert_v2 0 "$(cat test/control_test.d)"
assert_v2 0 "$(cat test/logical_test.d)"
assert_v2 0 "$(cat test/enum_test.d)"
assert_v2 0 "$(cat test/struct_test.d)"

# ==============================================================================
# Famous Snippets (Collatz, Primes, Queen, Switch, Multidim, Template)
# ==============================================================================
assert_v2 0 "$(cat test/collatz_test.d)"
assert_v2 0 "$(cat test/prime_test.d)"
assert_v2 0 "$(cat test/queen_test.d)"
assert_v2 0 "$(cat test/switch_test.d)"
assert_v2 0 "$(cat test/multidim_test.d)"
assert_v2 0 "$(cat test/template_test.d)"

# ==============================================================================
# Death Tests (Assert failure resulting in non-zero exit)
# ==============================================================================
assert_v2 1 "extern(C) int main() { assert(0); return 0; }"

# ==============================================================================
# Compile Failure Tests (TDD)
# ==============================================================================
assert_compile_fail "extern(C) int main() { int x; if (x = 1) {} return 0; }"
assert_compile_fail "extern(C) int main() { int x; int* p = &x; int res = 0 && (*p = 1); return 0; }"
assert_compile_fail "extern(C) int main() { int x = 3; switch (x) { case 3: x = 30; case 4: x = 35; break; default: break; } return 0; }"

# ==============================================================================
# Reference Compiler Verification (LDC)
# ==============================================================================
echo "Running LDC reference compiler verification on all test files..."
for test_file in test/arith_test.d test/control_test.d test/logical_test.d test/enum_test.d test/struct_test.d test/collatz_test.d test/prime_test.d test/queen_test.d test/switch_test.d test/multidim_test.d test/template_test.d; do
  echo "Verifying $test_file with LDC..."
  ldc2 -betterC "$test_file" test/ext.d -of=tmp_ldc_test
  actual_ldc="$?"
  if [ "$actual_ldc" != 0 ]; then
    echo "LDC compilation failed for $test_file"
    rm -f tmp_ldc_test
    exit 1
  fi
  ./tmp_ldc_test
  actual_ldc_exit="$?"
  rm -f tmp_ldc_test
  if [ "$actual_ldc_exit" != 0 ]; then
    echo "LDC execution failed for $test_file with exit code $actual_ldc_exit"
    exit 1
  fi
done
echo "All LDC reference compiler verifications passed!"

echo OK
