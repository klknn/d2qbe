#!/bin/bash

D2QBE=${D2QBE:-./d2qbe}

assert_v2() {
  expected="$1"
  input="$2"
  output="$3"

  $D2QBE "$input" | ./qbe/qbe > tmp.s
  cc -o tmp tmp.s ext.o
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

echo OK
