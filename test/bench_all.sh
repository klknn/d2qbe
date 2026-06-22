#!/bin/bash

echo "=== Three-Way End-to-End D Compiler Benchmark ==="

benchmarks=("test/mandel.d" "test/bench_collatz.d" "test/bench_prime.d" "test/bench_queen.d")
names=("Mandelbrot" "Collatz" "Primes" "N-Queens")

echo ""
echo "| Metric / Benchmark | Ours (d2qbe + dqbe) | Hybrid (d2qbe + QBE) | LDC2 -O3 (production) |"
echo "|-------------------|---------------------|----------------------|------------------------|"

for i in "${!benchmarks[@]}"; do
  src="${benchmarks[$i]}"
  name="${names[$i]}"
  
  # Compile with LDC
  ldc2 -O3 -betterC "$src" -of=bin_ldc >/dev/null 2>&1
  
  # Compile with Ours (d2qbe_opt + dqbe + cc)
  ./d2qbe "$src" > tmp.s 2>/dev/null
  ./dqbe < tmp.s > tmp_qbe.s 2>/dev/null
  cc -o bin_our tmp_qbe.s >/dev/null 2>&1
  rm -f tmp.s tmp_qbe.s
  
  # Compile with Hybrid (d2qbe_opt + upstream QBE + cc)
  ./d2qbe "$src" > tmp.s 2>/dev/null
  ./qbe/qbe < tmp.s > tmp_qbe.s 2>/dev/null
  cc -o bin_hybrid tmp_qbe.s >/dev/null 2>&1
  rm -f tmp.s tmp_qbe.s
  
  # Measure runtimes
  /usr/bin/time -f "%e" ./bin_our >/dev/null 2> /tmp/run_our.txt
  /usr/bin/time -f "%e" ./bin_hybrid >/dev/null 2> /tmp/run_hybrid.txt
  /usr/bin/time -f "%e" ./bin_ldc >/dev/null 2> /tmp/run_ldc.txt
  
  our_r=$(cat /tmp/run_our.txt)
  hybrid_r=$(cat /tmp/run_hybrid.txt)
  ldc_r=$(cat /tmp/run_ldc.txt)
  
  echo "| ${name} (Execution) | ${our_r} s | ${hybrid_r} s | ${ldc_r} s |"
  
  # Only report Compile Time and Memory for Mandelbrot to keep table clean
  if [ "$name" == "Mandelbrot" ]; then
    # Compile overhead measurements
    /usr/bin/time -f "%e %M" ldc2 -O3 -betterC "$src" -of=bin_ldc_c >/dev/null 2> /tmp/time_ldc.txt
    
    /usr/bin/time -f "%e %M" bash -c "./d2qbe $src > tmp.s && ./dqbe < tmp.s > tmp_qbe.s && cc -o bin_our_c tmp_qbe.s" >/dev/null 2> /tmp/time_our.txt
    
    /usr/bin/time -f "%e %M" bash -c "./d2qbe $src > tmp.s && ./qbe/qbe < tmp.s > tmp_qbe.s && cc -o bin_hybrid_c tmp_qbe.s" >/dev/null 2> /tmp/time_hybrid.txt
    
    rm -f tmp.s tmp_qbe.s bin_ldc_c bin_our_c bin_hybrid_c
    
    our_c_time=$(awk '{print $1}' /tmp/time_our.txt)
    our_c_mem=$(awk '{print $2}' /tmp/time_our.txt)
    
    hybrid_c_time=$(awk '{print $1}' /tmp/time_hybrid.txt)
    hybrid_c_mem=$(awk '{print $2}' /tmp/time_hybrid.txt)
    
    ldc_c_time=$(awk '{print $1}' /tmp/time_ldc.txt)
    ldc_c_mem=$(awk '{print $2}' /tmp/time_ldc.txt)
    
    LDC_SIZE=$(stat -c%s bin_ldc && strip bin_ldc && stat -c%s bin_ldc)
    OUR_SIZE=$(stat -c%s bin_our && strip bin_our && stat -c%s bin_our)
    HYBRID_SIZE=$(stat -c%s bin_hybrid && strip bin_hybrid && stat -c%s bin_hybrid)
    
    # Save compile metrics for reporting at the end
    MANDEL_OUR_C_TIME="$our_c_time"
    MANDEL_OUR_C_MEM="$our_c_mem"
    MANDEL_OUR_SIZE="$OUR_SIZE"
    
    MANDEL_HYBRID_C_TIME="$hybrid_c_time"
    MANDEL_HYBRID_C_MEM="$hybrid_c_mem"
    MANDEL_HYBRID_SIZE="$HYBRID_SIZE"
    
    MANDEL_LDC_C_TIME="$ldc_c_time"
    MANDEL_LDC_C_MEM="$ldc_c_mem"
    MANDEL_LDC_SIZE="$LDC_SIZE"
  fi
  
  rm -f bin_our bin_hybrid bin_ldc /tmp/run_our.txt /tmp/run_hybrid.txt /tmp/run_ldc.txt
done

echo "|-------------------|---------------------|----------------------|------------------------|"
echo "| Compile Time (Mandel) | ${MANDEL_OUR_C_TIME} s | ${MANDEL_HYBRID_C_TIME} s | ${MANDEL_LDC_C_TIME} s |"
echo "| Compile Memory (Mandel) | ${MANDEL_OUR_C_MEM} KB | ${MANDEL_HYBRID_C_MEM} KB | ${MANDEL_LDC_C_MEM} KB |"
echo "| Binary Size (Mandel) | ${MANDEL_OUR_SIZE} bytes | ${MANDEL_HYBRID_SIZE} bytes | ${MANDEL_LDC_SIZE} bytes |"

rm -f /tmp/time_ldc.txt /tmp/time_our.txt /tmp/time_hybrid.txt
