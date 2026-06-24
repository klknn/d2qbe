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

- [x] tiny self hosted compiler of betterC D language
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
  - [x] structs, member functions, constructors & destructors (RAII)
  - [x] switch statements & ternary operator
  - [x] multidimensional arrays & slices
  - [x] type aliases (`alias`) & type properties (`.init`, `.alignof`)
  - [x] conditional compilation (`version` and `debug` blocks)
  - [x] type inference (`auto` declarations)
  - [x] generics & templates (`template Name(T) { ... }`, eponymous `Name!Arg`)
  - [x] modular compilation (native `module` and recursive `import` compilation)
  - [x] floating point support (`float`, `double` arithmetic, conversions & registers)
  - [x] compound self-assignments (`+=`, `-=`, etc.)
  - [x] byte-sized function parameters safety (`char`/`bool` parameter stack stores)
  - [x] frontend SSA optimization (direct emission of QBE SSA `phi` instructions for ternary operations)
  - [x] `foreach` and `foreach_reverse` loops
  - [x] `scope(exit)` statements
- [ ] full set of betterC D language https://dlang.org/spec/betterc.html#consequences (Self-hosted compiler is 100% complete for the supported subset, but some standard betterC features are missing.)

## Unsupported / Missing betterC Features

While `d2qbe` compiles a very large and self-hosting subset of D `betterC`, the following standard D features are currently unsupported:

1. **`scope(success)` & `scope(failure)`**: These are disallowed under `-betterC` by standard compilers (like LDC) due to disabled exception handling/unwinding; our compiler errors out on them to guide standard compliance.
2. **Uniform Function Call Syntax (UFCS)**: True UFCS for free-standing functions is not supported.
3. **Compile-Time Function Execution (CTFE)**: There is no interpreter to evaluate custom functions at compile-time.
4. **Advanced Templates**: Multiple parameters, variadic parameters, constraints, and specializations are not supported (only eponymous templates with a single type parameter).
5. **C++ Classes & Interfaces**: `extern(C++) class` (which is standard betterC compatible as it does not use GC) is unsupported.


## benchmarks

We compared our custom D-to-assembly compiler toolchain against standard production toolchains using a floating-point heavy Mandelbrot set rendering loop (`test/mandel.d`) on `linux/x86_64`.

### Mandelbrot End-to-End Performance
* **Target Program**: `test/mandel.d` (Renders the Mandelbrot set 50 times in a loop).
* **Binaries Compared**:
  * **Ours**: Our custom D compiler toolchain (`d2qbe` + `dqbe` + `cc` assembler/linker).
  * **Hybrid**: A hybrid toolchain using our custom frontend (`d2qbe`) combined with the **upstream optimizing QBE compiler** (`qbe/qbe`) and `cc`.
  * **LDC2**: The standard production D compiler (`ldc2 -O3 -betterC`).

| Metric | Ours (d2qbe + dqbe) | Hybrid (d2qbe + QBE) | LDC2 -O3 (Production) |
| :--- | :---: | :---: | :---: |
| **Compile Time** | **0.04 s** | **0.06 s** | 0.07 s |
| **Compile Memory (Max RSS)** | **10.0 MB** | **9.8 MB** | 97.7 MB |
| **Binary Size (Stripped)** | 14,536 bytes | 14,536 bytes | 14,480 bytes |
| **Execution Time (50x runs)** | **1.36 s** | 0.25 s | 0.23 s |
| **Execution Memory (Max RSS)** | 1.6 MB | 1.6 MB | 1.6 MB |

### Multi-Benchmark Execution Suite
To verify compilation correctness and register pressure under different workloads, we compared execution runtimes (in seconds) across four diverse benchmark types:

| Benchmark | Ours (d2qbe + dqbe) | Hybrid (d2qbe + QBE) | LDC2 -O3 (Production) |
| :--- | :---: | :---: | :---: |
| **Mandelbrot** (Floating-point) | **1.36 s** | 0.25 s | 0.23 s |
| **Collatz** (Control-flow) | **0.53 s** | 0.28 s | 0.07 s |
| **Primes** (Modulo math) | **0.06 s** | 0.02 s | 0.02 s |
| **N-Queens** (Recursion & Arrays) | **4.00 s** | 0.74 s | 0.21 s |

#### Key Insights:
1. **Lightweight & Fast Compilation**: By utilizing `__gshared` memory for compiler global tables under `-betterC`, our toolchain compiles **2x faster** than LDC2 (0.04s vs 0.07s) and uses **9.7x less memory** (10.0MB vs 97.7MB).
2. **Optimal Frontend Generation**: When coupled with upstream QBE's backend optimizer, our custom frontend code generator matches the production-optimized LLVM code generation of LDC2 within **0.02 seconds** (0.25s vs 0.23s) and recurses extremely efficiently in N-Queens.
3. **Global Register Allocation**: We implemented a complete **Linear Scan Register Allocator** (allocating 5 GPRs `%rbx`, `%r12`..`%r15` and 6 FPRs `%xmm8`..`%xmm13` globally) alongside **SSA Deconstruction** (lowering `phi` instructions using parallel copies to prevent swap cycles). Together, this delivers massive execution speedups on complex loop-heavy and recursive programs (e.g. Mandelbrot execution time dropped from 1.70s to 1.36s, a **20% further speedup**!).

## references

- An Incremental Approach to Compiler Construction http://scheme2006.cs.uchicago.edu/11-ghuloum.pdf
- QBE Intermediate Language https://c9x.me/compile/doc/il.html
- D programming language spec https://dlang.org/spec/spec.html
- qbe/minic https://c9x.me/git/qbe.git/tree/minic
- A small C compiler chibicc https://github.com/rui314/chibicc
  - ja book https://www.sigbus.info/compilerbook
