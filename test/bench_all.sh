#!/bin/bash

echo "=== Three-Way End-to-End D Compiler Benchmark ==="
echo "Target: test/mandel.d (Mandelbrot set render loop)"

# 1. Compile with LDC
/usr/bin/time -f "%e %M" ldc2 -O3 -betterC test/mandel.d -of=mandel_ldc 2> /tmp/time_ldc.txt
LDC_COMPILE_TIME=$(cat /tmp/time_ldc.txt)

# 2. Compile with Ours (d2qbe_opt + dqbe + cc)
/usr/bin/time -f "%e %M" bash -c "./d2qbe_opt test/mandel.d > tmp_mandel.s && ./dqbe < tmp_mandel.s > tmp_mandel_qbe.s && cc -o mandel_our tmp_mandel_qbe.s && rm -f tmp_mandel.s tmp_mandel_qbe.s" 2> /tmp/time_our.txt
OUR_COMPILE_TIME=$(cat /tmp/time_our.txt)

# 3. Compile with Hybrid (d2qbe_opt + upstream QBE + cc)
/usr/bin/time -f "%e %M" bash -c "./d2qbe_opt test/mandel.d > tmp_mandel.s && ./qbe/qbe < tmp_mandel.s > tmp_mandel_qbe.s && cc -o mandel_hybrid tmp_mandel_qbe.s && rm -f tmp_mandel.s tmp_mandel_qbe.s" 2> /tmp/time_hybrid.txt
HYBRID_COMPILE_TIME=$(cat /tmp/time_hybrid.txt)

# Binary sizes
strip mandel_ldc
strip mandel_our
strip mandel_hybrid
LDC_SIZE=$(stat -c%s mandel_ldc)
OUR_SIZE=$(stat -c%s mandel_our)
HYBRID_SIZE=$(stat -c%s mandel_hybrid)

# 4. Execution speed & memory
/usr/bin/time -f "%e %M" ./mandel_ldc > /dev/null 2> /tmp/run_ldc.txt
LDC_RUN_TIME=$(cat /tmp/run_ldc.txt)

/usr/bin/time -f "%e %M" ./mandel_our > /dev/null 2> /tmp/run_our.txt
OUR_RUN_TIME=$(cat /tmp/run_our.txt)

/usr/bin/time -f "%e %M" ./mandel_hybrid > /dev/null 2> /tmp/run_hybrid.txt
HYBRID_RUN_TIME=$(cat /tmp/run_hybrid.txt)

# Report
echo ""
echo "| Metric | Ours (d2qbe + dqbe) | Hybrid (d2qbe + QBE) | LDC2 -O3 (production) |"
echo "|--------|---------------------|----------------------|------------------------|"

print_row() {
  name="$1"
  our_val="$2"
  hybrid_val="$3"
  ldc_val="$4"
  unit="$5"
  
  echo "| $name | $our_val $unit | $hybrid_val $unit | $ldc_val $unit |"
}

our_c_sec=$(awk '{print $1}' /tmp/time_our.txt)
our_c_mem=$(awk '{print $2}' /tmp/time_our.txt)

hybrid_c_sec=$(awk '{print $1}' /tmp/time_hybrid.txt)
hybrid_c_mem=$(awk '{print $2}' /tmp/time_hybrid.txt)

ldc_c_sec=$(awk '{print $1}' /tmp/time_ldc.txt)
ldc_c_mem=$(awk '{print $2}' /tmp/time_ldc.txt)

our_r_sec=$(awk '{print $1}' /tmp/run_our.txt)
our_r_mem=$(awk '{print $2}' /tmp/run_our.txt)

hybrid_r_sec=$(awk '{print $1}' /tmp/run_hybrid.txt)
hybrid_r_mem=$(awk '{print $2}' /tmp/run_hybrid.txt)

ldc_r_sec=$(awk '{print $1}' /tmp/run_ldc.txt)
ldc_r_mem=$(awk '{print $2}' /tmp/run_ldc.txt)

print_row "Compile Time" "$our_c_sec" "$hybrid_c_sec" "$ldc_c_sec" "s"
print_row "Compile Memory" "$our_c_mem" "$hybrid_c_mem" "$ldc_c_mem" "KB"
print_row "Binary Size" "$OUR_SIZE" "$HYBRID_SIZE" "$LDC_SIZE" "bytes"
print_row "Execution Time" "$our_r_sec" "$hybrid_r_sec" "$ldc_r_sec" "s"
print_row "Execution Memory" "$our_r_mem" "$hybrid_r_mem" "$ldc_r_mem" "KB"

# Clean up
rm -f mandel_ldc mandel_our mandel_hybrid /tmp/time_ldc.txt /tmp/time_our.txt /tmp/time_hybrid.txt /tmp/run_ldc.txt /tmp/run_our.txt /tmp/run_hybrid.txt
