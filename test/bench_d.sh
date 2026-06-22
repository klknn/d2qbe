#!/bin/bash

echo "=== End-to-End D Compiler Optimization Benchmark ==="
echo "Target: test/mandel.d (Mandelbrot set render loop)"

# Compile using LDC
/usr/bin/time -f "%e %M" ldc2 -O3 -betterC test/mandel.d -of=mandel_ldc 2> /tmp/time_ldc.txt
LDC_COMPILE_TIME=$(cat /tmp/time_ldc.txt)

# Compile using our toolchain (d2qbe_opt + dqbe + cc)
/usr/bin/time -f "%e %M" bash -c "./d2qbe_opt test/mandel.d > tmp_mandel.s && ./dqbe < tmp_mandel.s > tmp_mandel_qbe.s && cc -o mandel_our tmp_mandel_qbe.s && rm -f tmp_mandel.s tmp_mandel_qbe.s" 2> /tmp/time_our.txt
OUR_COMPILE_TIME=$(cat /tmp/time_our.txt)

# Binary size
strip mandel_ldc
strip mandel_our
LDC_SIZE=$(stat -c%s mandel_ldc)
OUR_SIZE=$(stat -c%s mandel_our)

# Execution speed
/usr/bin/time -f "%e %M" ./mandel_ldc > /dev/null 2> /tmp/run_ldc.txt
LDC_RUN_TIME=$(cat /tmp/run_ldc.txt)

/usr/bin/time -f "%e %M" ./mandel_our > /dev/null 2> /tmp/run_our.txt
OUR_RUN_TIME=$(cat /tmp/run_our.txt)

# Report
echo ""
echo "| Metric | our toolchain | ldc2 -O3 (production) | Ratio (ours / ldc2) |"
echo "|--------|---------------|------------------------|---------------------|"

print_metric() {
  name="$1"
  our_val="$2"
  ldc_val="$3"
  unit="$4"
  
  ratio=$(python3 -c "print(f'{float($our_val)/float($ldc_val):.2f}')")
  echo "| $name | $our_val $unit | $ldc_val $unit | $ratio |"
}

our_c_sec=$(echo "$OUR_COMPILE_TIME" | cut -d' ' -f1)
our_c_mem=$(echo "$OUR_COMPILE_TIME" | cut -d' ' -f2)

ldc_c_sec=$(echo "$LDC_COMPILE_TIME" | cut -d' ' -f1)
ldc_c_mem=$(echo "$LDC_COMPILE_TIME" | cut -d' ' -f2)

our_r_sec=$(echo "$OUR_RUN_TIME" | cut -d' ' -f1)
our_r_mem=$(echo "$OUR_RUN_TIME" | cut -d' ' -f2)

ldc_r_sec=$(echo "$LDC_RUN_TIME" | cut -d' ' -f1)
ldc_r_mem=$(echo "$LDC_RUN_TIME" | cut -d' ' -f2)

print_metric "Compile Time" "$our_c_sec" "$ldc_c_sec" "s"
print_metric "Compile Memory" "$our_c_mem" "$ldc_c_mem" "KB"
print_metric "Binary Size" "$OUR_SIZE" "$LDC_SIZE" "bytes"
print_metric "Execution Time" "$our_r_sec" "$ldc_r_sec" "s"
print_metric "Execution Memory" "$our_r_mem" "$ldc_r_mem" "KB"

# Clean up
rm -f mandel_ldc mandel_our /tmp/time_ldc.txt /tmp/time_our.txt /tmp/run_ldc.txt /tmp/run_our.txt
