#!/bin/bash

assert_v2() {
  expected="$1"
  input="$2"
  output="$3"

  ./d2qbe "$input" | ./qbe/qbe > tmp.s
  cc -o tmp tmp.s ext.o
  actual_output=$(./tmp)
  actual="$?"

  if [ "$actual" = "$expected" ]; then
    echo "$input => $actual"
  else
    echo "$input => $expected expected, but got $actual"
    exit 1
  fi
  if [ -n "$output" ]; then
  if [ "$actual_output" != "$output" ]; then
    echo "stdout: $output expected, but got $actual_output"
    exit 1
  fi
  fi
}

assert() {
  assert_v2 "$1" "main() { $2 }" "$3"
}

assert 0 "return 0;"
assert 42 "return 42;"
assert 21 'return 5+20-4;'
assert 41 'return 12 + 34 - 5 ;'
assert 47 'return 5+6*7;'
assert 15 'return 5*(9-6);'
assert 4 'return (3+5)/2;'
assert 10 'return -10+20;'
assert 10 'return - -10;'
assert 10 'return - - +10;'

assert 0 'return 0==1;'
assert 1 'return 42==42;'
assert 1 'return 0!=1;'
assert 0 'return 42!=42;'

assert 1 'return 0<1;'
assert 0 'return 1<1;'
assert 0 'return 2<1;'
assert 1 'return 0<=1;'
assert 1 'return 1<=1;'
assert 0 'return 2<=1;'

assert 1 'return 1>0;'
assert 0 'return 1>1;'
assert 0 'return 1>2;'
assert 1 'return 1>=0;'
assert 1 'return 1>=1;'
assert 0 'return 1>=2;'

assert 12 'returnx=12; return returnx;'
assert 12 'a=12; return a;'
assert 13 'a=12; return a+1;'
assert 10 'a=12;b=-2; return a+b;'
assert 12 'a=11; a = a + 1; return a;'
assert 10 'foo=12;bar=-2;return foo+bar;'

assert 1 "if (2>1) return 1; return 123;"
assert 1 "if (0) return 1; if (1) return 1; return 0;"
assert 123 "if (1>2) return 1; return 123;"
assert 1 "a=1;if (a) return 1; return 123;"
assert 123 "a=0;if (a) return 1; return 123;"
assert 1 "if (1) if (1) return 1; return 2;"
assert 2 "if (1) if (0) return 1; return 2;"
assert 0 "if (1) return 0; else if (0) return 1; else return 2;"
assert 1 "if (0) return 0; else if (1) return 1; else return 2;"
assert 2 "if (0) return 0; else if (0) return 1; else return 2;"
assert 2 "if (0) return 0; else if (0) return 1; else return 2;"
assert 1 "a = 0; if (1) a = 1; else a = 2; return a;"
assert 2 "a = 0; if (0) a = 1; else if (1) a = 2; else a = 3; return a;"

assert 10 "a=0; while(a<10) a = a + 1; return a;"
assert 0 "a=10; while(a>0) a = a - 1; return a;"
assert 10 "a=10; while(1) if (a>0)return a;return 0;"

assert 10 "for (a=0;a<10;a=a+1) a= a;return a;"
assert 0 "for (a=10;a>0;a=a-1) a= a;return a;"
assert 5 "for(a=0;a<10;a=a+1) if (a>5) return 5;return a;"
assert 10 "a=0;for (;a<10;) a=a+1;return a;"
assert 1 "a=0;for (;;) if (a<10)return 1;return 0;"

assert 1 "{ return 1; }"
assert 1 "{ a=1;return 1; }"
assert 3 "a=0;if (a==0) { a=3; if (a>3) return a; } return a;"
assert 4 "a=0;while(1) { a=a+1; if (a>3) return a; } return a;"
assert 10 "b=0;for(a=0;a<4;) { a=a+1;b=b+a; } return b;"
assert 1 "if (1) { a = 1; return a; } return 0;"
assert 2 "if(0) { a = 1; return a; } else { b = 2; return b; } return 0;"
assert 1 "if(1) { a = 1; if (1) { return a; } } else { b = 2; return b; } return 0;"

assert 0 "foo(); return 0;" "foo"
assert 0 "foo1(1); return 0;" "foo 1"
assert 0 "foo2(1, 2); return 0;" "foo 1 2"
assert 0 "foo2(1+2, 2); return 0;" "foo 3 2"
assert 0 "foo1(foo()); return 0;" "foo
foo 4"

assert_v2 3 "f(a){ return a+1; } main() { return f(2); }"
assert_v2 4 "f(a){ return a+1; } main() { return f(f(2)); }"
assert_v2 3 "
f(a){
  return a+1;
}

main() {
  return f(2);
}
"
assert_v2 55 "
fib(x) {
  if (x<=1)
    return 1;
  return fib(x-1) + fib(x-2);
}

main() {
  return fib(9);
}
"

assert_v2 12 "main() { a=12; b=&a; return *b; }"
#assert_v2 12 "main() { a=12; b=&a; c=&b; return **c; }"

echo OK
