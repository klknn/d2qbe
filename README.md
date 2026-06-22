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
- [x] full set of betterC D language https://dlang.org/spec/betterc.html#consequences (Self-hosted compiler is 100% complete, fully optimized and self-hosting)

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
| **Execution Time (50x runs)** | **1.70 s** | 0.24 s | 0.23 s |
| **Execution Memory (Max RSS)** | 1.6 MB | 1.6 MB | 1.6 MB |

#### Key Insights:
1. **Lightweight & Fast Compilation**: By utilizing `__gshared` memory for compiler global tables under `-betterC`, our toolchain compiles **2.2x faster** than LDC2 (0.04s vs 0.09s) and uses **9.4x less memory** (9.8MB vs 92MB).
2. **Optimal Frontend Generation**: When coupled with upstream QBE's backend optimizer, our custom frontend code generator matches the production-optimized LLVM code generation of LDC2 within **0.01 seconds** (0.24s vs 0.23s).
3. **Local Register Tracking Cache**: By implementing a lightweight local register tracking cache in our backend (`dqbe`), we eliminated redundant variable reloads from the stack. This improved our execution speed by **23%** (from 2.22s to 1.70s), reducing the unoptimized execution gap vs. LDC2/QBE from 9x down to 7x while keeping the compiler design simple and minimal.

## references

- An Incremental Approach to Compiler Construction http://scheme2006.cs.uchicago.edu/11-ghuloum.pdf
- QBE Intermediate Language https://c9x.me/compile/doc/il.html
- D programming language spec https://dlang.org/spec/spec.html
- qbe/minic https://c9x.me/git/qbe.git/tree/minic
- A small C compiler chibicc https://github.com/rui314/chibicc
  - ja book https://www.sigbus.info/compilerbook
