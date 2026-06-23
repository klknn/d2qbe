#!/bin/bash
set -e

# Rebuild clean compiler
make clean > /dev/null
make > /dev/null
ldc2 -O3 -betterC -Isource -c source/dqbe/tokenize.d -of=dqbe_tokenize.o
ldc2 -O3 -betterC -Isource -c source/dqbe/parse.d -of=dqbe_parse.o
ldc2 -O3 -betterC -Isource -c source/dqbe/regalloc.d -of=dqbe_regalloc.o
ldc2 -O3 -betterC -Isource -c source/dqbe/codegen.d -of=dqbe_codegen.o
ldc2 -O3 -betterC -Isource -c source/dqbe/app.d -of=dqbe_app.o
ldc2 -O3 -betterC -Isource dqbe_tokenize.o dqbe_parse.o dqbe_regalloc.o dqbe_codegen.o dqbe_app.o test/tmp_ext_all.o -of=dqbe
rm -f dqbe_*.o

# Prepare self_host_dqbe.d
cat << 'EOF' > test/self_host_dqbe.d
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
extern (C) int printf(const(char)*, ...);
extern (C) int fprintf(void*, const(char)*, ...);
extern (C) void exit(int);
extern (C) double strtod(const(char)*, void*);

extern (C) void* get_stderr();
extern (C) void* get_stdin();
extern (C) void* get_stdout();

alias long = int;
EOF

for f in source/dqbe/tokenize.d source/dqbe/parse.d source/dqbe/regalloc.d source/dqbe/codegen.d source/dqbe/app.d; do
  grep -v '^import ' "$f" | grep -v '^module ' >> test/self_host_dqbe.d
done

# Compile tmp_ext_all.o
ldc2 -betterC -c test/tmp_ext_all.d -of=test/tmp_ext_all.o

# Helper to run /usr/bin/time and extract real time + max RSS
run_timed() {
  cmd="$1"
  # Run command and capture time output to temp file
  /usr/bin/time -v sh -c "$cmd" 2> tmp_time.txt
  
  # Extract min:sec or sec. E.g. "0:01.23" or "0:00.05"
  time_str=$(grep "Elapsed (wall clock) time" tmp_time.txt | awk '{print $NF}')
  
  # Convert "mm:ss.hh" to seconds
  if [[ "$time_str" == *":"* ]]; then
    minutes=$(echo "$time_str" | cut -d: -f1)
    seconds=$(echo "$time_str" | cut -d: -f2)
    total_sec=$(echo "scale=2; $minutes * 60 + $seconds" | bc)
  else
    total_sec="$time_str"
  fi
  
  rss=$(grep "Maximum resident set size" tmp_time.txt | awk '{print $NF}')
  # RSS is in KB. Convert to MB.
  rss_mb=$(echo "scale=1; $rss / 1024" | bc)
  
  echo "$total_sec $rss_mb"
}

echo "Running benchmarks..."

# 1. Frontend compilation (d2qbe compiling 3000-line self_host_dqbe.d)
frontend_stats=$(run_timed "./d2qbe \"\$(cat test/self_host_dqbe.d)\" > test/self_host_dqbe.s")
fe_time=$(echo "$frontend_stats" | awk '{print $1}')
fe_mem=$(echo "$frontend_stats" | awk '{print $2}')

# 2. Backend assembling: Ours (dqbe)
ours_stats=$(run_timed "./dqbe < test/self_host_dqbe.s > test/self_host_dqbe_qbe.s")
ours_time=$(echo "$ours_stats" | awk '{print $1}')
ours_mem=$(echo "$ours_stats" | awk '{print $2}')

# 3. Backend assembling: Upstream (QBE)
upstream_stats=$(run_timed "./qbe/qbe < test/self_host_dqbe.s > test/self_host_dqbe_upstream.s")
upstream_time=$(echo "$upstream_stats" | awk '{print $1}')
upstream_mem=$(echo "$upstream_stats" | awk '{print $2}')

# Assemble and link self-hosted binaries
cc -o test/dqbe_self_hosted test/self_host_dqbe_qbe.s test/tmp_ext_all.o
cc -o test/dqbe_hybrid test/self_host_dqbe_upstream.s test/tmp_ext_all.o

strip test/dqbe_self_hosted
strip test/dqbe_hybrid

# Measure binary sizes
size_ours=$(wc -c < test/dqbe_self_hosted)
size_hybrid=$(wc -c < test/dqbe_hybrid)

# 4. Program execution time: Compile bench_queen.d using both, run 10 times
# Ours
./d2qbe "$(cat test/bench_queen.d)" | ./test/dqbe_self_hosted > tmp_queen_ours.s
cc -o tmp_queen_ours tmp_queen_ours.s test/tmp_ext_all.o
exec_ours=$(run_timed "./tmp_queen_ours")
exec_ours_time=$(echo "$exec_ours" | awk '{print $1}')
exec_ours_mem=$(echo "$exec_ours" | awk '{print $2}')

# Hybrid
./d2qbe "$(cat test/bench_queen.d)" | ./test/dqbe_hybrid > tmp_queen_hybrid.s
cc -o tmp_queen_hybrid tmp_queen_hybrid.s test/tmp_ext_all.o
exec_hybrid=$(run_timed "./tmp_queen_hybrid")
exec_hybrid_time=$(echo "$exec_hybrid" | awk '{print $1}')
exec_hybrid_mem=$(echo "$exec_hybrid" | awk '{print $2}')

# Clean up
rm -f tmp_time.txt tmp_queen_ours.s tmp_queen_ours tmp_queen_hybrid.s tmp_queen_hybrid

# Output Markdown Table
echo "=== Self-Hosting Compiler Benchmark Suite ==="
echo ""
echo "| Metric | Ours (d2qbe + dqbe) | Hybrid (d2qbe + QBE) |"
echo "| :--- | :---: | :---: |"
echo "| Frontend Compile Time | $fe_time s | $fe_time s |"
echo "| Frontend Compile Memory | $fe_mem MB | $fe_mem MB |"
echo "| Backend Assemble Time | $ours_time s | $upstream_time s |"
echo "| Backend Assemble Memory | $ours_mem MB | $upstream_mem MB |"
echo "| Self-Hosted Compiler Binary Size | $size_ours bytes | $size_hybrid bytes |"
echo "| Executed N-Queens Time (12 Queens) | $exec_ours_time s | $exec_hybrid_time s |"
echo "| Executed N-Queens Memory | $exec_ours_mem MB | $exec_hybrid_mem MB |"
echo ""
