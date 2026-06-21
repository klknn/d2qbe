#!/bin/bash
set -e

# Concatenate compiler source files
cat << 'EOF' > test/self_host_dqbe.d
// C stdlib declarations
extern (C) void* calloc(int nmemb, int size);
extern (C) void* malloc(int size);
extern (C) void* realloc(void* ptr, int size);
extern (C) void free(void* ptr);
extern (C) int fread(void* ptr, int size, int nmemb, void* stream);
extern (C) void* memcpy(void* dest, const void* src, int n);
extern (C) int strcmp(const char* s1, const char* s2);
extern (C) int strlen(const char* s);
extern (C) int strncmp(const char* s1, const char* s2, int n);
extern (C) int memcmp(const void* s1, const void* s2, int n);
extern (C) int strtol(const char* nptr, char** endptr, int base);
extern (C) int isspace(int c);
extern (C) int isdigit(int c);
extern (C) char* strchr(const char* s, int c);
extern (C) int printf(const char* format, ...);
extern (C) int fprintf(void* stream, const char* format, ...);
extern (C) void exit(int status);

extern (C) void* get_stderr();
extern (C) void* get_stdin();
extern (C) void* get_stdout();

alias float = int;
alias double = long;
enum null = 0;
EOF

# Strip imports and modules from source files and append
for f in source/dqbe/tokenize.d source/dqbe/parse.d source/dqbe/codegen.d source/dqbe/app.d; do
  grep -v '^import ' "$f" | grep -v '^module ' >> test/self_host_dqbe.d
done

# Compile stream helper functions
ldc2 -betterC -c test/tmp_ext_all.d -of=test/tmp_ext_all.o

echo "Compiling self_host_dqbe.d using bootstrap compiler..."
./d2qbe "$(cat test/self_host_dqbe.d)" > test/self_host_dqbe.s

echo "Assembling self_host_dqbe.s using dqbe..."
./dqbe < test/self_host_dqbe.s > test/self_host_dqbe_qbe.s
cc -o test/dqbe_self_hosted test/self_host_dqbe_qbe.s test/tmp_ext_all.o

echo "Verifying self-hosted compiler using dqbe backend..."

assert_dqbe() {
  expected="$1"
  input="$2"
  echo "Testing: $input => $expected"
  ./d2qbe "$input" | ./test/dqbe_self_hosted > tmp.s
  cc -o tmp tmp.s test/tmp_ext_all.o
  actual=0
  ./tmp || actual="$?"
  if [ "$actual" -ne "$expected" ]; then
    echo "FAILED: Expected $expected, but got $actual"
    exit 1
  fi
}

assert_dqbe_file() {
  expected="$1"
  file_path="$2"
  echo "Testing file: $file_path => $expected"
  ./d2qbe "$(cat $file_path)" | ./test/dqbe_self_hosted > tmp.s
  cc -o tmp tmp.s test/tmp_ext_all.o
  actual=0
  ./tmp || actual="$?"
  if [ "$actual" -ne "$expected" ]; then
    echo "FAILED: Expected $expected, but got $actual"
    exit 1
  fi
}

# Run key test cases
assert_dqbe 0 "int main() { return 0; }"
assert_dqbe 42 "int main() { return 42; }"
assert_dqbe 21 "int main() { return 5+20-4; }"
assert_dqbe 15 "int main() { return 5*(9-6); }"
assert_dqbe 1 "int main() { return 0==0; }"
assert_dqbe 0 "int main() { return 0==1; }"
assert_dqbe 10 "int main() { int a=12; int b=-2; return a+b; }"
assert_dqbe 10 "int main() { int a=0; while(a<10) a = a + 1; return a; }"
assert_dqbe 55 "int fib(int x) { if (x<=1) return 1; return fib(x-1) + fib(x-2); } int main() { return fib(9); }"
assert_dqbe 12 "int main() { int a=12; int* b=&a; return *b; }"
assert_dqbe 2 "int main() { return 10 % 4; }"
assert_dqbe 2 "int main() { return 2 & 3; }"
assert_dqbe 40 "int main() { return 10 << 2; }"

# Run full integration test files
assert_dqbe_file 0 "test/arith_test.d"
assert_dqbe_file 0 "test/control_test.d"
assert_dqbe_file 0 "test/logical_test.d"
assert_dqbe_file 0 "test/enum_test.d"
assert_dqbe_file 0 "test/struct_test.d"
assert_dqbe_file 0 "test/collatz_test.d"
assert_dqbe_file 0 "test/prime_test.d"
assert_dqbe_file 0 "test/queen_test.d"
assert_dqbe_file 0 "test/switch_test.d"
assert_dqbe_file 0 "test/multidim_test.d"
assert_dqbe_file 0 "test/template_test.d"

# Clean up temp files
rm -f tmp tmp.s

echo "Self-hosting verification with dqbe PASSED!"
