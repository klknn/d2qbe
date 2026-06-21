#!/bin/bash
set -e

# Concatenate compiler source files
cat << 'EOF' > test/self_host.d
// C stdlib declarations
extern (C) void* calloc(int nmemb, int size);
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

enum null = 0;
EOF

# Strip imports and modules from source files and append
for f in source/d2qbe/tokenize.d source/d2qbe/parse.d source/d2qbe/codegen.d source/d2qbe/app.d; do
  grep -v '^import ' "$f" | grep -v '^module ' >> test/self_host.d
done

# Strip comments and empty lines to reduce file size
python3 -c "
import re
with open('test/self_host.d', 'r') as f:
    content = f.read()
content = re.sub(r'/\*.*?\*/', '', content, flags=re.DOTALL)
content = re.sub(r'//.*', '', content)
content = '\n'.join([l for l in content.split('\n') if l.strip()])
with open('test/self_host.d', 'w') as f:
    f.write(content)
"

echo "Compiling self_host.d using bootstrap compiler..."
./d2qbe test/self_host.d > test/self_host.s

echo "Assembling self_host.s..."
./qbe/qbe < test/self_host.s > test/self_host_qbe.s
cc -o test/d2qbe_self_hosted test/self_host_qbe.s ext.o

echo "Running tests using self-hosted compiler..."
D2QBE=./test/d2qbe_self_hosted ./test/run.sh

echo "Self-hosting test PASSED!"
