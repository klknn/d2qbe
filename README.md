# d2qbe: D language to QBE language compiler

## usage

how to compile executables step-by-step.

```bash
make all
./d2qbe "main { return 0; }" > a.ssa
./qbe/qbe < a.ssa > a.s
cc a.s -o a.out
./a.out
```

## roadmap

- [ ] tiny self hosted compiler of betterC D language
  - [x] int arith
  - [x] int variables
  - [x] control statements (if-else, for, while)
  - [x] external call of functions precompiled with ldc2
  - [x] multi-int to single int function def and call
  - [x] pointer
  - [x] sizeof
  - [x] array (pointer arithmetic and indexing)
  - [x] global variables
  - [x] string
  - [ ] struct
  - [ ] initializer
- [ ] full set of betterC D language https://dlang.org/spec/betterc.html#consequences

## benchmarks

We compared our custom D-to-assembly compiler toolchain against standard production toolchains using a floating-point heavy Mandelbrot set rendering loop (`test/mandel.d`) on `linux/x86_64`.

### Three-Way End-to-End D Compiler Benchmark
* **Target Program**: `test/mandel.d` (Renders the Mandelbrot set 50 times in a loop).
* **Binaries Compared**:
  * **Ours**: Our custom D compiler toolchain (`d2qbe_opt` + `dqbe` + `cc` assembler/linker).
  * **Hybrid**: A hybrid toolchain using our custom frontend (`d2qbe_opt`) combined with the **upstream optimizing QBE compiler** (`qbe/qbe`) and `cc`.
  * **LDC2**: The standard production D compiler (`ldc2 -O3 -betterC`).

| Metric | Ours (d2qbe + dqbe) | Hybrid (d2qbe + QBE) | LDC2 -O3 (Production) |
| :--- | :---: | :---: | :---: |
| **Compile Time** | **0.04 s** | **0.04 s** | 0.09 s |
| **Compile Memory (Max RSS)** | **9.8 MB** | **9.8 MB** | 92.3 MB |
| **Binary Size (Stripped)** | 14,536 bytes | 14,536 bytes | 14,480 bytes |
| **Execution Time (50x runs)** | 2.22 s | 0.24 s | 0.23 s |
| **Execution Memory (Max RSS)** | 1.6 MB | 1.6 MB | 1.6 MB |

#### Key Insights:
1. **Lightweight & Fast Compilation**: By utilizing `__gshared` memory for compiler global tables under `-betterC`, our toolchain compiles **2.2x faster** than LDC2 (0.04s vs 0.09s) and uses **9.4x less memory** (9.8MB vs 92MB).
2. **Optimal Frontend Generation**: When coupled with upstream QBE's backend optimizer, our custom frontend code generator matches the production-optimized LLVM code generation of LDC2 within **0.01 seconds** (0.24s vs 0.23s).
3. **Optimized vs. Unoptimized Execution Speed**: The 9x execution speed gap of our pure toolchain (2.22s vs. 0.24s) is entirely due to our custom backend compiler `dqbe` doing simple variable-to-stack slots allocation instead of running SSA optimizations.

## references

- An Incremental Approach to Compiler Construction http://scheme2006.cs.uchicago.edu/11-ghuloum.pdf
- QBE Intermediate Language https://c9x.me/compile/doc/il.html
- D programming language spec https://dlang.org/spec/spec.html
- qbe/minic https://c9x.me/git/qbe.git/tree/minic
- A small C compiler chibicc https://github.com/rui314/chibicc
  - ja book https://www.sigbus.info/compilerbook
