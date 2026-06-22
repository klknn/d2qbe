#!/bin/bash

echo "=== Backend Code Generation Benchmark: dqbe vs upstream QBE ==="
echo "Target: Flat QBE IR generated from test/mandel.d"
echo "Compiling 50 times to get measurable compile time..."

# 1. Generate flat QBE IR
./d2qbe_opt test/mandel.d > tmp_mandel.s

# 2. Compile using dqbe 50 times
/usr/bin/time -f "%e %M" bash -c "for i in {1..50}; do ./dqbe < tmp_mandel.s > tmp_dqbe.s; done" 2> /tmp/time_dqbe.txt
DQBE_COMPILE_TIME=$(cat /tmp/time_dqbe.txt)

# 3. Compile using upstream QBE 50 times
/usr/bin/time -f "%e %M" bash -c "for i in {1..50}; do ./qbe/qbe < tmp_mandel.s > tmp_qbe.s; done" 2> /tmp/time_qbe.txt
QBE_COMPILE_TIME=$(cat /tmp/time_qbe.txt)

# 4. Link
cc -o mandel_dqbe tmp_dqbe.s
cc -o mandel_qbe tmp_qbe.s

# Binary size
strip mandel_dqbe
strip mandel_qbe
DQBE_SIZE=$(stat -c%s mandel_dqbe)
QBE_SIZE=$(stat -c%s mandel_qbe)

# 5. Execution speed
/usr/bin/time -f "%e %M" ./mandel_dqbe > /dev/null 2> /tmp/run_dqbe.txt
DQBE_RUN_TIME=$(cat /tmp/run_dqbe.txt)

/usr/bin/time -f "%e %M" ./mandel_qbe > /dev/null 2> /tmp/run_qbe.txt
QBE_RUN_TIME=$(cat /tmp/run_qbe.txt)

# Report
echo ""
echo "| Metric | dqbe (ours) | QBE (upstream) | Ratio (dqbe / QBE) |"
echo "|--------|-------------|----------------|--------------------|"

print_metric() {
  name="$1"
  dqbe_val="$2"
  qbe_val="$3"
  unit="$4"
  
  ratio=$(python3 -c "print(f'{float($dqbe_val)/float($qbe_val):.2f}')")
  echo "| $name | $dqbe_val $unit | $qbe_val $unit | $ratio |"
}

dqbe_c_sec=$(awk '{print $1}' /tmp/time_dqbe.txt)
dqbe_c_mem=$(awk '{print $2}' /tmp/time_dqbe.txt)

qbe_c_sec=$(awk '{print $1}' /tmp/time_qbe.txt)
qbe_c_mem=$(awk '{print $2}' /tmp/time_qbe.txt)

dqbe_r_sec=$(awk '{print $1}' /tmp/run_dqbe.txt)
dqbe_r_mem=$(awk '{print $2}' /tmp/run_dqbe.txt)

qbe_r_sec=$(awk '{print $1}' /tmp/run_qbe.txt)
qbe_r_mem=$(awk '{print $2}' /tmp/run_qbe.txt)

print_metric "Compile Time (50x)" "$dqbe_c_sec" "$qbe_c_sec" "s"
print_metric "Compile Memory" "$dqbe_c_mem" "$qbe_c_mem" "KB"
print_metric "Binary Size" "$DQBE_SIZE" "$QBE_SIZE" "bytes"
print_metric "Execution Time" "$dqbe_r_sec" "$qbe_r_sec" "s"
print_metric "Execution Memory" "$dqbe_r_mem" "$qbe_r_mem" "KB"

# Clean up
rm -f tmp_mandel.s tmp_dqbe.s tmp_qbe.s mandel_dqbe mandel_qbe /tmp/time_dqbe.txt /tmp/time_qbe.txt /tmp/run_dqbe.txt /tmp/run_qbe.txt
